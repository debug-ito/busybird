use strict;
use warnings;
use lib 't/lib';
use utf8;
use Test::More;
use Test::MockObject;
use DateTime;
use DateTime::Duration;
use BusyBird::Main;
use BusyBird::StatusStorage::Memory;
use BusyBird::DateTime::Format;
use BusyBird::Test::HTTP;
use BusyBird::Test::StatusStorage qw(:status test_cases_for_ack);
use BusyBird::Test::Timeline_Util qw(status);
use BusyBird::Log ();
use Plack::Test;
use Encode ();
use JSON qw(encode_json decode_json);
use Try::Tiny;

$BusyBird::Log::LOGGER = undef;

sub create_main {
    my $main = BusyBird::Main->new();
    $main->default_status_storage(BusyBird::StatusStorage::Memory->new);
    return $main;
}

sub create_dying_status_storage {
    my $mock = Test::MockObject->new();
    foreach my $method (map { "${_}_statuses" } qw(ack get put delete)) {
        $mock->mock($method, sub {
            die "$method dies.";
        });
    }
    ## ** We cannot create a Timeline if get_unacked_counts throws an exception.
    $mock->mock('get_unacked_counts', sub {
        my ($self, %args) = @_;
        $args{callback}->(undef, "get_unacked_counts reports error.");
    });
    return $mock;
}

sub create_erroneous_status_storage {
    my $mock = Test::MockObject->new();
    foreach my $method ('get_unacked_counts', map { "${_}_statuses" } qw(ack get put delete)) {
        $mock->mock($method, sub {
            my ($self, %args) = @_;
            my $cb = $args{callback};
            if($cb) {
                $cb->("$method reports error.");
            }
        });
    }
    return $mock;
}

sub create_json_status {
    my ($id, $level) = @_;
    my $created_at_str = BusyBird::DateTime::Format->format_datetime(
        DateTime->from_epoch(epoch => $id, time_zone => 'UTC')
    );
    my $bb_string = defined($level) ? qq{,"busybird":{"level":$level}} : "";
    my $json_status = <<EOD;
{"id":"$id","created_at":"$created_at_str","text":"テキスト $id"$bb_string}
EOD
    return Encode::encode('utf8', $json_status);
}

sub json_array {
    my (@json_objects) = @_;
    return "[".join(",", @json_objects)."]";
}

sub test_get_statuses {
    my ($tester, $timeline_name, $query_str, $exp_id_list, $label) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $request_url = "/timelines/$timeline_name/statuses.json";
    if($query_str) {
        $request_url .= "?$query_str";
    }
    my $res_obj = $tester->get_json_ok($request_url, qr/^200$/, "$label: GET statuses OK");
    is($res_obj->{error}, undef, "$label: GET statuses error = null OK");
    test_status_id_list($res_obj->{statuses}, $exp_id_list, "$label: GET statuses ID list OK");
}

sub test_error_request {
    my ($tester, $endpoint, $content, $label) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ($method, $request_url) = split(/ +/, $endpoint);
    $label ||= "";
    my $msg = "$label: $endpoint returns error";
    $tester->request_ok($method, $request_url, $content, qr/^[45]/, $msg);
}

{
    note('--- normal functionalities');
    my $main = create_main();
    $main->timeline('test');
    $main->timeline('foobar');

    test_psgi $main->to_app, sub {
        my $tester = BusyBird::Test::HTTP->new(requester => shift);
        test_get_statuses($tester, 'test', undef, [], 'No status');
        my $res_obj = $tester->post_json_ok('/timelines/test/statuses.json',
                                           create_json_status(1), qr/^200$/, 'POST statuses (single) OK');
        is_deeply($res_obj, {error => undef, count => 1}, "POST statuses (single) results OK");
        $res_obj = $tester->post_json_ok('/timelines/test/statuses.json',
                                       json_array(map {create_json_status($_, $_)} 1..5),
                                       qr/^200$/, 'POST statuses (multi) OK');
        is_deeply($res_obj, {error => undef, count => 4}, "POST statuses (multi) results OK");

        test_get_statuses($tester, 'test', 'count=100', [reverse 1..5], "Get all");
        test_get_statuses($tester, 'test', 'ack_state=acked', [], 'only acked');
        test_get_statuses($tester, 'test', 'ack_state=unacked', [reverse 1..5], 'only unacked');

        $res_obj = $tester->post_json_ok('/timelines/test/ack.json', undef, qr/^200$/, 'POST ack (no param) OK');
        is_deeply($res_obj, {error => undef, count => 5}, 'POST ack (no param) results OK');

        $res_obj = $tester->post_json_ok('/timelines/test/statuses.json',
                                         json_array(map {
                                             my $id = $_;
                                             my $level = $id <= 10 ? undef
                                                 : $id <= 20 ? 1 : 2;
                                             create_json_status($id, $level)
                                         } 6..30), qr/^200$/, 'POST statuses (25) OK');
        is_deeply($res_obj, {error => undef, count => 25}, 'POST statuses (25) OK');

        test_get_statuses($tester, 'test', undef, [reverse 11..30], 'Get no count');
        test_get_statuses($tester, 'test', 'ack_state=acked', [reverse 1..5], 'Get only acked');
        test_get_statuses($tester, 'test', 'max_id=20&count=30', [reverse 1..20], 'max_id and count');
        test_get_statuses($tester, 'test', 'max_id=20&count=30&ack_state=unacked', [reverse 6..20], 'max_id, count and ack_state');
        test_get_statuses($tester, 'test', 'max_id=20&count=30&ack_state=acked', [], 'max_id in unacked, ack_state = acked');
        test_get_statuses($tester, 'test', 'max_id=60', [], 'unknown max_id');
        test_get_statuses($tester, 'test', 'max_id=23', [reverse 4..23], 'only max_id');

        {
            my $exp_res = {error => undef, unacked_counts => {total => 25, 0 => 5, 1 => 10, 2 => 10}};
            foreach my $case (
                {label => "no param", param => ""},
                {label => "total", param => "?total=20"},
                {label => "level 0", param => "?0=3"},
                {label => "only level 1 differs", param => "?1=9&2=10&0=5&total=25"},
            ) {
                $res_obj = $tester->get_json_ok("/timelines/test/updates/unacked_counts.json$case->{param}",
                                                qr/^200$/, "GET tl unacked_counts ($case->{label}) OK");
                is_deeply($res_obj, $exp_res, "GET tl unacked_counts ($case->{label}) result OK");
            }
        }
        
        $res_obj = $tester->post_json_ok('/timelines/test/ack.json', qq{{"max_id":"100"}}, qr/^200$/, 'POST ack (unknown max_id) OK');
        is_deeply($res_obj, {error => undef, count => 0}, 'POST ack (unknown max_id) acks nothing');
        $res_obj = $tester->post_json_ok('/timelines/test/ack.json', qq{{"max_id":"4"}}, qr/^200$/, 'POST ack (acked max_id) OK');
        is_deeply($res_obj, {error => undef, count => 0}, 'POST ack (acked max_id) acks nothing');
        $res_obj = $tester->post_json_ok('/timelines/test/ack.json', qq{{"max_id":"20"}}, qr/^200$/, 'POST ack (unacked max_id) OK');
        is_deeply($res_obj, {error => undef, count => 15}, 'POST ack (unacked max_id) acks OK');

        test_get_statuses($tester, 'test', 'ack_state=unacked&count=100', [reverse 21..30], 'unacked');
        test_get_statuses($tester, 'test', 'ack_state=acked&count=100', [reverse 1..20], 'acked');

        $res_obj = $tester->post_json_ok('/timelines/foobar/statuses.json',
                                         json_array(map {create_json_status($_, $_ % 2 ? 2 : -2)} 1..10),
                                         qr/^200$/, 'POST statuses to foobar OK');
        is_deeply($res_obj, {error => undef, count => 10}, 'POST statuses result OK');
        
        {
            my $exp_tl_test = {error => undef, unacked_counts => {
                test => { total => 10, 2 => 10 }
            }};
            my $exp_tl_foobar = {error => undef, unacked_counts => {
                foobar => { total => 10,  -2 => 5, 2 => 5 }
            }};
            foreach my $case (
                {label => "total, 1 TL", param => '?level=total&tl_test=0', exp => $exp_tl_test},
                {label => "no level, TL test right", param => '?tl_test=10&tl_foobar=5', exp => $exp_tl_foobar},
                {label => "level -2, TL foobar right", param => '?level=-2&tl_foobar=5&tl_test=5', exp => $exp_tl_test},
                {label => "level -2, TL test right", param => '?level=-2&tl_foobar=3&tl_test=0', exp => $exp_tl_foobar},
                {label => "level 2, TL foobar right", param => '?level=2&tl_test=0&tl_foobar=5', exp => $exp_tl_test},
                {label => "level 2, TL test right", param => '?level=2&tl_test=10&tl_foobar=12', exp => $exp_tl_foobar},
                {label => "level 3, TL test right", param => '?level=3&tl_test=0&tl_foobar=1', exp => $exp_tl_foobar},
                {label => "total, 1 TL 2 junk TLs", param => '?level=total&tl_junk=6&tl_hoge=0&tl_test=0', exp => $exp_tl_test},
            ) {
                $res_obj = $tester->get_json_ok("/updates/unacked_counts.json$case->{param}",
                                                qr/^200$/, "GET /updates/unacked_counts.json ($case->{label}) OK");
                is_deeply($res_obj, $case->{exp}, "GET /updates/unacked_counts.json ($case->{label}) results OK");
            }
        }
    };
}

{
    note('--- -- various POST ack argument patterns');
    my $f = 'BusyBird::DateTime::Format';
    foreach my $case (test_cases_for_ack(is_ordered => 0), test_cases_for_ack(is_ordered => 1)) {
        note("--- POST ack case: $case->{label}");
        my $main = create_main();
        $main->timeline('test');
        test_psgi $main->to_app, sub {
            my $tester = BusyBird::Test::HTTP->new(requester => shift);
            my $already_acked_at = $f->format_datetime(
                DateTime->now(time_zone => 'UTC') - DateTime::Duration->new(days => 1)
            );
            my $input_statuses = [
                (map {status($_,0,$already_acked_at)} 1..10),
                (map {status($_)} 11..20)
            ];
            my $res_obj = $tester->post_json_ok('/timelines/test/statuses.json',
                                                encode_json($input_statuses), qr/^200$/, 'POST statuses OK');
            is_deeply($res_obj, {error => undef, count => 20}, "POST count OK");
            my $request_message = defined($case->{req}) ? encode_json($case->{req}) : undef;
            $res_obj = $tester->post_json_ok('/timelines/test/ack.json', $request_message, qr/^200$/, 'POST ack OK');
            is_deeply($res_obj, {error => undef, count => $case->{exp_count}}, "ack count is $case->{exp_count}");
            test_get_statuses($tester, 'test', 'ack_state=unacked&count=100', $case->{exp_unacked}, 'unacked statuses OK');
            test_get_statuses($tester, 'test', 'ack_state=acked&count=100', $case->{exp_acked}, 'acked statuses OK');
        };
    }
}

{
    my $main = create_main();
    $main->timeline('test');
    note('--- GET /updates/unacked_counts.json with no valid TL');
    test_psgi $main->to_app, sub {
        my $tester = BusyBird::Test::HTTP->new(requester => shift);
        foreach my $case (
            {label => "no params", param => ""},
            {label => "junk TLs and params", param => "?tl_hoge=10&tl_foo=1&bar=3&_=1020"}
        ) {
            my $res_obj = $tester->get_json_ok("/updates/unacked_counts.json$case->{param}",
                                               qr/^[45]/,
                                               "GET /updates/unacked_counts.json ($case->{label}) returns error");
            ok(defined($res_obj->{error}), ".. $case->{label}: error is set");
        }
    };
}

{
    my $main = create_main();
    $main->timeline('test');
    note('--- Not Found cases');
    test_psgi $main->to_app, sub {
        my $tester = BusyBird::Test::HTTP->new(requester => shift);
        foreach my $case (
            {endpoint => "GET /timelines/foobar/statuses.json"},
            {endpoint => "GET /timelines/foobar/updates/unacked_counts.json"},
            {endpoint => "POST /timelines/foobar/ack.json"},
            {endpoint => "POST /timelines/foobar/statuses.json", content => create_json_status(1)},
            {endpoint => "POST /timelines/test/statuses.json"},
            {endpoint => "POST /timelines/test/updates/unacked_counts.json"},
            {endpoint => "GET /timelines/test/ack.json"},
            {endpoint => "POST /updates/unacked_counts.json?tl_test=10"},
        ) {
            test_error_request($tester, $case->{endpoint}, $case->{content});
        }
    };
}

{
    foreach my $storage_case (
        {label => "dying", storage => create_dying_status_storage()},
        {label => "erroneous", storage => create_erroneous_status_storage()},
    ) {
        note("--- $storage_case->{label} status storage");
        my $main = create_main();
        $main->default_status_storage($storage_case->{storage});
        $main->timeline('test');
        test_psgi $main->to_app, sub {
            my $tester = BusyBird::Test::HTTP->new(requester => shift);
            foreach my $case (
                {endpoint => "GET /timelines/test/statuses.json"},
                ## {endpoint => "GET /timelines/test/updates/unacked_counts.json"},
                {endpoint => "POST /timelines/test/ack.json"},
                {endpoint => "POST /timelines/test/statuses.json", content => create_json_status(1)},
                ## {endpoint => "GET /updates/unacked_counts.json?tl_test=3"}
            ) {
                test_error_request($tester, $case->{endpoint}, $case->{content}, $storage_case->{label});
            }
        }
    }
}

{
    my $main = create_main();
    $main->timeline('test');
    note('--- status with weird ID');
    test_psgi $main->to_app, sub {
        my $tester = BusyBird::Test::HTTP->new(requester => shift);
        my $weird_id_status = {
            id => q{!"#$%&'(){}=*+>< []\\|/-_;^~@`?: 3},
            created_at => "Thu Jan 01 00:00:03 +0000 1970",
            text => q{変なIDのステータス。},
        };
        my $encoded_id = '%21%22%23%24%25%26%27%28%29%7B%7D%3D%2A%2B%3E%3C%20%5B%5D%5C%7C%2F-_%3B%5E~%40%60%3F%3A%203';
        my $res_obj = $tester->post_json_ok('/timelines/test/statuses.json',
                                            json_array(map { create_json_status($_) } 1,2,4,5),
                                            qr/^200$/, 'POST normal statuses OK');
        is_deeply($res_obj, {error => undef, count => 4}, "POST normal statuses results OK");
        $res_obj = $tester->post_json_ok('/timelines/test/statuses.json',
                                         encode_json($weird_id_status), qr/^200$/, 'POST weird status OK');
        is_deeply($res_obj, {error => undef, count => 1}, 'POST weird status OK');

        test_get_statuses($tester, 'test', "max_id=$encoded_id&count=10",
                          [$weird_id_status->{id}, 2, 1], 'max_id = weird ID');
        
        $res_obj = $tester->post_json_ok('/timelines/test/ack.json',
                                         encode_json({max_id => $weird_id_status->{id}}),
                                         qr/^200$/, 'POST ack max_id = weird ID OK');
        is_deeply($res_obj, {error => undef, count => 3}, "POST ack max_id = weird ID results OK");

        test_get_statuses($tester, 'test', 'ack_state=unacked', [5,4], "GET unacked");
        test_get_statuses($tester, 'test', 'ack_state=acked', [$weird_id_status->{id}, 2, 1], 'GET acked');
    };
}

{
    note('--- For examples');
    my $main = create_main();
    my @cases = (
        {endpoint => 'POST /timelines/home/statuses.json',
         content => <<EOD,
[
  {
    "id": "http://example.com/page/2013/0204",
    "created_at": "Mon Feb 04 11:02:45 +0900 2013",
    "text": "content of the status",
    "busybird": { "level": 3 }
  },
  {
    "id": "http://example.com/page/2013/0202",
    "created_at": "Sat Feb 02 17:38:12 +0900 2013",
    "text": "another content"
  }
]
EOD
         exp_response => q{{"error": null, "count": 2}}},
        {endpoint => 'GET /timelines/home/statuses.json?count=1&ack_state=any&max_id=http://example.com/page/2013/0202',
         exp_response => <<EOD},
{
  "error": null,
  "statuses": [
    {
      "id": "http://example.com/page/2013/0202",
      "created_at": "Sat Feb 02 17:38:12 +0900 2013",
      "text": "another content"
    }
  ]
}
EOD
        {endpoint => 'GET /timelines/home/updates/unacked_counts.json?total=2&0=2',
         exp_response => <<EOD},
{
  "error": null,
  "unacked_counts": {
    "total": 2,
    "0": 1,
    "3": 1
  }
}
EOD
        {endpoint => 'GET /updates/unacked_counts.json?level=total&tl_home=0&tl_foobar=0',
         exp_response => <<EOD},
{
  "error": null,
  "unacked_counts": {
    "home": {
      "total": 2,
      "0": 1,
      "3": 1
    }
  }
}
EOD
        {endpoint => 'POST /timelines/home/ack.json',
         content => <<EOD,
{
  "max_id": "http://example.com/page/2013/0202",
  "ids": [
    "http://example.com/page/2013/0204",
   ]
}
EOD
         exp_response => q{{"error": null, "count": 2}}}
    );
    test_psgi $main->to_app, sub {
        my $tester = BusyBird::Test::HTTP->new(requester => shift);
        foreach my $case (@cases) {
            my ($method, $request_url) = split(/ +/, $case->{endpoint});
            my $res_obj = $tester->request_json_ok($method, $request_url, $case->{content},
                                                   qr/^200$/, "$case->{endpoint} OK");
            my $exp_obj = decode_json($case->{exp_response});
            is_deeply($res_obj, $exp_obj, "$case->{endpoint} response OK");
        }
    };
}

fail('todo: GET statuses: html format');

done_testing();

