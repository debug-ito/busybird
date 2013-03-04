use strict;
use warnings;
use lib 't/lib';
use utf8;
use Test::More;
use DateTime;
use BusyBird::Main;
use BusyBird::StatusStorage::Memory;
use BusyBird::DateTime::Format;
use BusyBird::Test::HTTP;
use BusyBird::Test::StatusStorage qw(:status);
use Plack::Test;
use Encode ();

sub create_main {
    my $main = BusyBird::Main->new();
    $main->default_status_storage(BusyBird::StatusStorage::Memory->new);
    return $main;
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
    is($res_obj->{is_success}, JSON::true, "$label: GET statuses is_success OK");
    test_status_id_list($res_obj->{statuses}, $exp_id_list, "$label: GET statuses ID list OK");
}

{
    my $main = create_main();
    $main->timeline('test');
    $main->timeline('foobar');

    test_psgi $main->to_app, sub {
        my $tester = BusyBird::Test::HTTP->new(requester => shift);
        test_get_statuses($tester, 'test', undef, [], 'No status');
        my $res_obj = $tester->post_json_ok('/timelines/test/statuses.json',
                                           create_json_status(1), qr/^200$/, 'POST statuses (single) OK');
        is_deeply($res_obj, {is_success => JSON::true, count => 1}, "POST statuses (single) results OK");
        $res_obj = $tester->post_json_ok('/timelines/test/statuses.json',
                                       json_array(map {create_json_status($_, $_)} 1..5),
                                       qr/^200$/, 'POST statuses (multi) OK');
        is_deeply($res_obj, {is_success => JSON::true, count => 4}, "POST statuses (multi) results OK");

        test_get_statuses($tester, 'test', 'count=100', [reverse 1..5], "Get all");
        test_get_statuses($tester, 'test', 'ack_state=acked', [], 'only acked');
        test_get_statuses($tester, 'test', 'ack_state=unacked', [reverse 1..5], 'only unacked');

        $res_obj = $tester->post_json_ok('/timelines/test/ack.json', undef, qr/^200$/, 'POST ack (no param) OK');
        is_deeply($res_obj, {is_success => JSON::true, count => 5}, 'POST ack (no param) results OK');

        $res_obj = $tester->post_json_ok('/timelines/test/statuses.json',
                                         json_array(map {
                                             my $id = $_;
                                             my $level = $id <= 10 ? undef
                                                 : $id <= 20 ? 1 : 2;
                                             create_json_status($id, $level)
                                         } 6..30), qr/^200$/, 'POST statuses (25) OK');
        is_deeply($res_obj, {is_success => JSON::true, count => 25}, 'POST statuses (25) OK');

        test_get_statuses($tester, 'test', undef, [reverse 11..30], 'Get no count');
        test_get_statuses($tester, 'test', 'ack_state=acked', [reverse 1..5], 'Get only acked');
        test_get_statuses($tester, 'test', 'max_id=20&count=30', [reverse 1..20], 'max_id and count');
        test_get_statuses($tester, 'test', 'max_id=20&count=30&ack_state=unacked', [reverse 6..20], 'max_id, count and ack_state');
        test_get_statuses($tester, 'test', 'max_id=20&count=30&ack_state=acked', [], 'max_id in unacked, ack_state = acked');
        test_get_statuses($tester, 'test', 'max_id=60', [], 'unknown max_id');
        test_get_statuses($tester, 'test', 'max_id=23', [reverse 4..23], 'only max_id');

        {
            my $exp_res = {is_success => JSON::true, unacked_counts => {total => 25, 0 => 5, 1 => 10, 2 => 10}};
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
        is_deeply($res_obj, {is_success => JSON::true, count => 0}, 'POST ack (unknown max_id) acks nothing');
        $res_obj = $tester->post_json_ok('/timelines/test/ack.json', qq{{"max_id":"4"}}, qr/^200$/, 'POST ack (acked max_id) OK');
        is_deeply($res_obj, {is_success => JSON::true, count => 0}, 'POST ack (acked max_id) acks nothing');
        $res_obj = $tester->post_json_ok('/timelines/test/ack.json', qq{{"max_id":"20"}}, qr/^200$/, 'POST ack (unacked max_id) OK');
        is_deeply($res_obj, {is_success => JSON::true, count => 15}, 'POST ack (unacked max_id) acks OK');

        test_get_statuses($tester, 'test', 'ack_state=unacked&count=100', [reverse 21..30], 'unacked');
        test_get_statuses($tester, 'test', 'ack_state=acked&count=100', [reverse 1..20], 'acked');

        $res_obj = $tester->post_json_ok('/timelines/foobar/statuses.json',
                                         json_array(map {create_json_status($_, $_ % 2 ? 2 : -2)} 1..10),
                                         qr/^200$/, 'POST statuses to foobar OK');
        is_deeply($res_obj, {is_success => JSON::true, count => 10}, 'POST statuses result OK');
        
        {
            my $exp_tl_test = {is_success => JSON::true, unacked_counts => {
                test => { total => 10, 2 => 10 }
            }};
            my $exp_tl_foobar = {is_success => JSON::true, unacked_counts => {
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
            ) {
                $res_obj = $tester->get_json_ok("/updates/unacked_counts.json$case->{param}",
                                                qr/^200$/, "GET /updates/unacked_counts.json ($case->{label}) OK");
                is_deeply($res_obj, $case->{exp}, "GET /updates/unacked_counts.json ($case->{label}) results OK");
            }
        }
    };
}

fail('todo: GET statuses: max_id of URL-encoded ID');
fail('todo: GET statuses: html format');
fail('todo: GET /updates/unacked_counts.json with no TL');
fail('todo: test with dying storage. test with storage returning errors.');
fail('todo: examples');
fail('todo: test 404');

done_testing();

