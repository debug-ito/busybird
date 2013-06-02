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
use BusyBird::Main::PSGI;
use BusyBird::StatusStorage::Memory;

$BusyBird::Log::Logger = undef;

{
    my $main = BusyBird::Main->new;
    $main->set_config(default_status_storage => BusyBird::StatusStorage::Memory->new);
    my @statuses = map { status($_, $_ + 10) } 0..9;
    $main->timeline('test')->add(\@statuses);
    test_psgi create_psgi_app($main), sub {
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

{
    note("--- various status ID renderings");
    my $main = BusyBird::Main->new;
    $main->set_config(default_status_storage => BusyBird::StatusStorage::Memory->new);
    my $timeline = $main->timeline('test');
    foreach my $case (
        {in_id => 'http://example.com/', exp_id => 'http://example.com/'},
        {in_id => 'crazy<>ID', exp_id => 'crazy&lt;&gt;ID'},
        {in_id => 'crazier<span>ID</span>', exp_id => 'crazier&lt;span&gt;ID&lt;/span&gt;'},
        {in_id => 'ID with space', exp_id => 'ID with space'},
    ) {
        $timeline->delete_statuses(ids => undef);
        my $in_status = { id => $case->{in_id} };
        $timeline->add([$in_status]);
        test_psgi create_psgi_app($main), sub {
            my $tester = BusyBird::Test::HTTP->new(requester => shift);
            my @statuses_html = BusyBird::Test::StatusHTML->new_multiple($tester->request_ok(
                "GET", "/timelines/test/statuses.html?count=100", undef,
                qr/^200$/, "GET statuses.html OK"
            ));
            is(scalar(@statuses_html), 1, "1 status node");
            is($statuses_html[0]->id, $case->{exp_id}, "In ID: $case->{in_id} OK");
        };
    }
}

done_testing();

