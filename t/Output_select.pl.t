
use strict;
use warnings;

use Test::More;
use Test::AnyEvent::Time;

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
    my ($output, $condition, $exp_num) = @_;
    $output->select(
        sub {
            my ($sid, %res) = @_;
            $called++;
            ok(defined($res{new_statuses_num}));
            cmp_ok($res{new_statuses_num}, "==", $exp_num, "status num: $res{new_statuses_num} == $exp_num");
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

sub checkSelectNum {
    my ($output, $select_input, $exp_num) = @_;
    selectStatusNum($output, $select_input, $exp_num);
    testCalled 1;
}

{
    my $out = new_ok('BusyBird::Output', [name => 'test', no_persistent => 1]);
    selectStatusNum($out, 0, 1);
    testCalled 0;
    syncPush($out, createStatus(1));
    testCalled 1;

    selectStatusNum($out, [0], 1);
    testCalled 1;
    selectStatusNum($out, [1], 4);
    testCalled 0;
    syncPush($out, map {createStatus($_)} (2..4));
    testCalled 1;

    selectStatusNum($out, [4, 4], 5);
    testCalled 0;
    syncPush($out, map {createStatus($_, 5)} (5..7));
    testCalled 0;
    syncPush($out, map {createStatus($_, 2)} (8));
    testCalled 1;

    curLevels $out, 2, 5, 5, 5, undef, undef, undef, undef;
    
    selectStatusNum($out, [4, 0], 7);
    testCalled 0;
    syncPush($out, createStatus(9, 0), map { createStatus($_, -3) } (10, 11));
    testCalled 1;

    curLevels $out, 0, -3, -3, 2, 5, 5, 5, undef, undef, undef, undef;

    checkSelectNum($out, 2000, 11);
    checkSelectNum($out, [2000, 0], 7);
    checkSelectNum($out, [2000, -2], 2);
    checkSelectNum($out, [2000, 5], 11);
    checkSelectNum($out, [2000, 10], 11);
    checkSelectNum($out, {size => 2000}, 11);
    checkSelectNum($out, {size => 2000, level => 1}, 7);
    checkSelectNum($out, {size => 2000, level => -1}, 2);
    checkSelectNum($out, {size => 2000, level => 0}, 7);

    done_testing();
}
