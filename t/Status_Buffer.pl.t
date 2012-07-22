
use strict;
use warnings;

use Test::More;
use JSON;

BEGIN {
    use_ok('DateTime');
    use_ok('BusyBird::Status');
    use_ok('BusyBird::Status::Buffer');
}


my $next_id = 1;
sub createStatus {
    my ($id, $val) = @_;
    if(!$id) {
        $id = $next_id;
        $next_id++;
    }
    $val ||= $id;
    return new_ok(
        'BusyBird::Status', [
            id => $id,
            id_str => "$id",
            created_at => DateTime->from_epoch(epoch => $id),
            val => "$val",
        ]
    );
}

sub checkGotStatuses {
    my ($buf, $start, $length, @exp_ids) = @_;
    note(sprintf("--- get(%s, %s)", defined($start) ? $start : "[undef]", defined($length) ? $length : "[undef]"));
    my $got_status = $buf->get($start, $length);
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
    checkGotStatuses($buf, undef, undef, ());
    checkGotStatuses($buf, 5, undef, ());
    checkGotStatuses($buf, 6, 10, ());
    checkGotStatuses($buf, 6, 10, ());
    checkGotStatuses($buf, -10, undef, ());
    checkGotStatuses($buf, 3, -10, ());
    checkGotStatuses($buf, -10, 22, ());
    checkGotStatuses($buf, undef, 10, ());

    note("--- unshift 5 statuses");
    $buf->unshift(&createStatus()) foreach 1..5;
    is($buf->size, 5);
    ok($buf->contains($_), "contains ID: $_ (number)") foreach 1..5;
    ok($buf->contains(&createStatus($_)), "contains ID: $_ (status)") foreach 1..5;
    checkGotStatuses($buf, undef, undef, reverse(1..5));
    checkGotStatuses($buf, 3, undef, reverse(1..2));
    checkGotStatuses($buf, 0, 2, reverse(4, 5));
    checkGotStatuses($buf, 1, 3, reverse(2..4));
    checkGotStatuses($buf, undef, 4, reverse(2..5));
    checkGotStatuses($buf, -3, undef, reverse(1..3));
    checkGotStatuses($buf, 0, -2, reverse(3..5));
    checkGotStatuses($buf, undef, -3, reverse(4..5));
    checkGotStatuses($buf, 2, -1, reverse(2..3));
    checkGotStatuses($buf, 3, 8, reverse(1..2));
    checkGotStatuses($buf, 10, undef, ());
    checkGotStatuses($buf, -21, undef, ());
    checkGotStatuses($buf, 1, -4, ());
    checkGotStatuses($buf, undef, -10, ());
    $buf->truncate();
    is($buf->size, 5);

    note("--- test sort()");
    $buf->clear();
    is($buf->size, 0);
    $buf->unshift(
        &createStatus(29, "ubuntu"),
        &createStatus(12, "slackware"),
        &createStatus(3, "fedora"),
        &createStatus(43, "centos"),
        &createStatus(33, "debian"),
        &createStatus(1102, "vine"),
    );
    checkGotStatuses($buf, undef, undef, (29, 12, 3, 43, 33, 1102));
    $buf->unshift(
        &createStatus(33, "DEBIAN"),
        &createStatus(1102, "VINE"),
    );
    is($buf->size, 6);
    checkGotStatuses($buf, undef, undef, (29, 12, 3, 43, 33, 1102));
    $buf->sort();
    checkGotStatuses($buf, undef, undef, (1102, 43, 33, 29, 12, 3));
    $buf->sort(sub {$_[0]->{val} cmp $_[1]->{val}});
    checkGotStatuses($buf, undef, undef, (43, 33, 3, 12, 29, 1102));

    note("--- test truncate()");
    $buf = new_ok("BusyBird::Status::Buffer", [max_size => 10]);
    $next_id = 10;
    $buf->unshift(&createStatus($_)) foreach 1..30;
    checkGotStatuses($buf, undef, undef, reverse(1..30));
    $buf->truncate();
    checkGotStatuses($buf, undef, undef, reverse(21..30));
}

{
    note("--- test JSONize");
    my $buf = new_ok("BusyBird::Status::Buffer", [max_size => 200]);
    $next_id = 1;
    $buf->unshift(&createStatus($_, "val$_")) foreach 1..30;
    my $json_text = to_json($buf, {ascii => 1, allow_blessed => 1, convert_blessed => 1});
    my $decoded = from_json($json_text);
    is(ref($decoded), "ARRAY", '$decoded is an arrayref');
    is(int(@$decoded), 30, "... and has 30 items.");
    foreach my $i (0 .. $#$decoded) {
        my $status = $decoded->[$i];
        my $exp_id = 30 - $i;
        my $exp_val = "val$exp_id";
        is($status->{id}, $exp_id, "Status index $i has ID $exp_id.");
        is($status->{val}, $exp_val, "... and val $exp_val");
    }
}

done_testing();


