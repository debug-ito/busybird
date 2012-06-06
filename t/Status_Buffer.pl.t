
use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('DateTime');
    use_ok('BusyBird::Status');
    use_ok('BusyBird::Status::Buffer');
}


my $next_id = 1;
sub createStatus {
    my ($id) = @_;
    if(!$id) {
        $id = $next_id;
        $next_id++;
    }
    return new_ok(
        'BusyBird::Status', [
            id => $id,
            id_str => "$id",
            created_at => DateTime->from_epoch(epoch => $id),
        ]
    );
}

sub checkGotStatuses {
    my ($got_status, @exp_ids) = @_;
    is(ref($got_status), 'ARRAY', "got_status is an array");
    cmp_ok(int(@$got_status), '==', int(@exp_ids), "got_status size ok");
    foreach my $i (0 .. $#$got_status) {
        my $status = $got_status->[$i];
        isa_ok($status, 'BusyBird::Status');
        cmp_ok($status->{id}, '==', $exp_ids[$i]);
    }
}

{
    my $buf = new_ok('BusyBird::Status::Buffer');
    checkGotStatuses($buf->get(), ());
    checkGotStatuses($buf->get(5), ());
    checkGotStatuses($buf->get(6, 10), ());
    checkGotStatuses($buf->get(6, 10), ());
    checkGotStatuses($buf->get(-10), ());
    checkGotStatuses($buf->get(3, -10), ());
    checkGotStatuses($buf->get(-10, 22), ());

    note("--- unshift 5 statuses");
    $buf->unshift(&createStatus()) foreach 1..5;
    is($buf->size, 5);
    ok($buf->contains($_), "contains ID: $_ (number)") foreach 1..5;
    ok($buf->contains(&createStatus($_)), "contains ID: $_ (status)") foreach 1..5;
    checkGotStatuses($buf->get(), reverse(1..5));
    checkGotStatuses($buf->get(3), reverse(1..2));
    checkGotStatuses($buf->get(0, 2), reverse(4, 5));
    checkGotStatuses($buf->get(1, 3), reverse(2..4));
}

done_testing();


