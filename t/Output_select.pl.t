
use strict;
use warnings;

use Test::More;
use Test::AnyEvent::Time;
use Test::Warn;

BEGIN {
    use_ok('BusyBird::Status');
    use_ok('BusyBird::Output');
}

sub createStatus {
    my ($id, $level) = @_;
    my $status = BusyBird::Status->new(
        created_at => '2000-01-01T08:00:00+0000',
        id => $id,
        id_str => "$id",
    );
    if(@_ >= 2) {
        $status->{busybird}{level} = $level;
    }
    return $status;
}

my $called = 0;

sub testCalled {
    my $exp = shift;
    cmp_ok($called, "==", $exp, "called is $exp");
    if($exp) {
        $called = 0;
    }
}

sub selectStatusNum {
    my ($output, $condition, $exp_set) = @_;
    $output->select(
        sub {
            my ($sid, %res) = @_;
            $called++;
            ok(defined($res{new_statuses_num}));
            ## cmp_ok($res{new_statuses_num}, "==", $exp_num, "status num: $res{new_statuses_num} == $exp_num");
            is_deeply($res{new_statuses_num}, $exp_set, "got resource as expected.");
            return 1;
        },
        new_statuses_num => $condition
    );
}

sub syncPush {
    my ($output, @statuses) = @_;
    time_within_ok sub {
        my $cv = shift;
        $output->pushStatuses([@statuses], sub { $cv->send });
    }, 10;
}

sub curLevels {
    my ($output, @exp_levels) = @_;
    my $statuses = $output->getNewStatuses;
    my $exp_num = int(@exp_levels);
    cmp_ok(int(@$statuses), "==", $exp_num, "all new statuses num: $exp_num");
    foreach my $i (0 .. $#exp_levels) {
        if(defined($exp_levels[$i])) {
            cmp_ok($statuses->[$i]{busybird}{level}, "==", $exp_levels[$i], "status $i: level $exp_levels[$i]");
        }else {
            ok(!defined($statuses->[$i]{busybird}{level}), "status $i: level undef");
        }
    }
}

{
    my $out = new_ok('BusyBird::Output', [name => 'test', no_persistent => 1]);
    selectStatusNum($out, 0, {total => 1, 0 => 1});
    testCalled 0;
    syncPush($out, createStatus(1));
    testCalled 1;

    selectStatusNum($out, 0, {total => 1, 0 => 1});
    testCalled 1;
    selectStatusNum($out, 1, {total => 4, 0 => 4});
    testCalled 0;
    syncPush($out, map {createStatus($_)} (2..4));
    testCalled 1;

    selectStatusNum($out, 4, {total => 7, 0 => 4, 5 => 3});
    testCalled 0;
    syncPush($out, map {createStatus($_, 5)} (5..7));
    testCalled 1;
    selectStatusNum($out, 7, {total => 8, 0 => 4, 2 => 1, 5 => 3});
    testCalled 0;
    syncPush($out, map {createStatus($_, 2)} (8));
    testCalled 1;

    curLevels $out, 2, 5, 5, 5, undef, undef, undef, undef;
    
    selectStatusNum($out, 8, {total => 11, -3 => 2, 0 => 5, 2 => 1, 5 => 3});
    testCalled 0;
    syncPush($out, createStatus(9, 0), map { createStatus($_, -3) } (10, 11));
    testCalled 1;

    curLevels $out, 0, -3, -3, 2, 5, 5, 5, undef, undef, undef, undef;

    foreach my $junk (undef, "hogehoge", "23sfh", [10, 10], {foo => 10, bar => 9}) {
        warning_like {
            $out->select(sub { return 1 }, new_statuses_num => undef);
        } qr/must be a number/, "error on select";
    }

    done_testing();
}
