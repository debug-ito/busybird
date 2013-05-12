use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::RealBin/lib";
use BusyBird::Log;
use BusyBird::Test::HTTP;
use BusyBird::Test::Timeline_Util qw(status);
use BusyBird::Test::StatusHTML;
use Plack::Test;
use BusyBird::Main;
use BusyBird::StatusStorage::Memory;

$BusyBird::Log::Logger = undef;

{
    my $main = BusyBird::Main->new;
    $main->default_status_storage(BusyBird::StatusStorage::Memory->new);
    my @statuses = map { status($_, $_ + 10) } 0..9;
    $main->timeline('test')->add(\@statuses);
    test_psgi $main->to_app, sub {
        my $tester = BusyBird::Test::HTTP->new(requester => shift);
        my @statuses_html = BusyBird::Test::StatusHTML->new_multiple($tester->request_ok(
            "GET", "/timelines/test/statuses.html?count=5&max_id=7", undef,
            qr/^200$/, "GET statuses.html OK"
        ));
        is(scalar(@statuses_html), 5, "5 status nodes");
        my @exp_ids = reverse(3 .. 7);
        my @exp_levels = reverse(13 .. 17);
        foreach my $status_html (@statuses_html) {
            my $exp_id = shift(@exp_ids);
            my $exp_level = shift(@exp_levels);
            is($status_html->level, $exp_level, "status node level OK");
            is($status_html->id, $exp_id, "status node ID OK");
        }
    };
}

done_testing();

