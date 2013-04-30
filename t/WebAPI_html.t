use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::RealBin/lib";
use BusyBird::Log;
use BusyBird::Test::HTTP;
use BusyBird::Test::Timeline_Util qw(status);
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
        my $tree = $tester->request_htmltree_ok(
            "GET", "/timelines/test/statuses.html?count=5&max_id=7", undef,
            qr/^200$/, "GET statuses.html OK"
        );
        my @status_nodes = $tree->findnodes('//li');
        is(scalar(@status_nodes), 5, "5 status nodes");
        my @exp_ids = reverse(3 .. 7);
        my @exp_levels = reverse(13 .. 17);
        foreach my $status_node (@status_nodes) {
            my $exp_id = shift(@exp_ids);
            my $exp_level = shift(@exp_levels);
            like($status_node->attr('class'), qr/bb-status/, "status node should have bb-status class");
            is($status_node->attr('data-bb-status-level'), $exp_level, "status node level OK");
            my @id_nodes = $status_node->findnodes('.//*[@class="bb-status-id"]');
            is(scalar(@id_nodes), 1, "status node has only 1 ID node");
            my @id_content = $id_nodes[0]->content_list;
            is(scalar(@id_content), 1, "ID node has only 1 content");
            is($id_content[0], $exp_id, "... and it's status ID");
        }
    };
}

done_testing();

