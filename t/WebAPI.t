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

{
    my $main = BusyBird::Main->new();
    $main->default_status_storage(BusyBird::StatusStorage::Memory->new);
    $main->timeline('test');

    test_psgi $main->to_app, sub {
        my $tester = BusyBird::Test::HTTP->new(requester => shift);
        my $res_obj = $tester->post_json_ok('/timelines/test/statuses.json',
                                           create_json_status(1), qr/^200$/, 'POST statuses (single) OK');
        is_deeply($res_obj, {is_success => JSON::true, count => 1}, "POST statuses (single) results OK");
        $res_obj = $tester->post_json_ok('/timelines/test/statuses.json',
                                       json_array(map {create_json_status($_, $_)} 1..5),
                                       qr/^200$/, 'POST statuses (multi) OK');
        is_deeply($res_obj, {is_success => JSON::true, count => 4}, "POST statuses (multi) results OK");

        $res_obj = $tester->get_json_ok('/timelines/test/statuses.json?count=100', qr/^200$/, 'GET statuses OK');
        is($res_obj->{is_success}, JSON::true, "GET statuses is_success OK");
        test_status_id_set($res_obj->{statuses}, [1..5], "GET statuses ID set OK");
    };
}

fail('todo: GET statuses: max_id, ack_state, count');
fail("todo: GET statuses: count = 20 by default");

done_testing();

