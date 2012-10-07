
## The test is originally for BusyBird::Filter.

use strict;
use warnings;

use Test::More;
use Test::Exception;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use EV;
use Pseudo::CV;

BEGIN {
    use_ok('BusyBird::Defer::Queue');
}

sub checkFilter {
    my ($filter, $input_seq, $expected_seq) = @_;
    my $cv = Pseudo::CV->new;
    $filter->run(sub { $cv->send($_[0]) }, $input_seq);
    my $got_seq = $cv->recv();
    is_deeply($got_seq, $expected_seq);
}

sub filterPlus {
    my $add_amount = shift;
    return sub {
        my ($d, $statuses) = @_;
        $_ += $add_amount foreach @$statuses;
        my $tw; $tw = EV::timer 0.1, 0, sub {
            undef $tw;
            $d->done($statuses);
        };
    };
}

sub filterReverse {
    return sub {
        my ($d, $statuses) = @_;
        my $tw; $tw = EV::timer 0.1, 0, sub {
            undef $tw;
            $d->done( [reverse(@$statuses)] );
        };
    };
}

sub filterSleepPush {
    my ($pushval, $sleep) = @_;
    return sub {
        my ($d, $in) = @_;
        note(sprintf('filterSleepPush with pushval => %s, sleep => %s', $pushval, $sleep));
        my $tw; $tw = EV::timer $sleep, 0,  sub {
            undef $tw;
            push(@$in, $pushval);
            $d->done($in);
        };
    };
}

sub filterCheck {
    my ($expected_seq) = @_;
    return sub {
        my ($d, $statuses) = @_;
        is_deeply($statuses, $expected_seq, "filterCheck");
        my $tw; $tw = EV::timer 0.1, 0, sub {
            undef $tw;
            $d->done($statuses);
        };
    }
}

sub filterDying {
    my ($add, $msg, $is_in_place) = @_;
    return sub {
        my ($d, $statuses) = @_;
        my $tw; $tw = EV::timer 0.2, 0, sub {
            undef $tw;
            my @new_statuses = ();
            eval {
                foreach my $i (0 .. $#$statuses) {
                    if($is_in_place) {
                        $statuses->[$i] += $add;
                    }else {
                        push(@new_statuses, $statuses->[$i] + $add);
                    }
                    die "$msg" if $i == int(@$statuses / 2);
                }
            };
            if($@) {
                note("filterDying dies: $@");
            }
            $d->done($is_in_place ? $statuses : \@new_statuses);
        }
    };
}

sub checkParallel {
    my ($parallel_limit, $try_count, $expect_max_parallel, $expect_order_ref) = @_;
    note("--- -- checkParallel limit => $parallel_limit, try_count => $try_count, expect_max_parallel => $expect_max_parallel");
    my $filter = BusyBird::Defer::Queue->new(max_active => $parallel_limit);
    $expect_max_parallel ||= $parallel_limit;
    my $parallel_count = 0;
    my $filter_done_count = 0;
    my $got_max_parallel = 0;
    $filter->do(
        sub {
            my ($d, $target) = @_;
            my $tw; $tw = EV::timer 0, 0, sub {
                undef $tw;
                $parallel_count++;
                if($parallel_limit > 0) {
                    cmp_ok($parallel_count, '<=', $parallel_limit, "Parallel count <= $parallel_limit");
                }
                $got_max_parallel = $parallel_count if $parallel_count > $got_max_parallel;
                $d->done($target);
            };
        }
    );
    $filter->do(
        sub {
            my ($d, $target) = @_;
            ## ** descending amount of sleep_time
            my $sleep_time = 3.0 / $target;
            my $tw; $tw = EV::timer $sleep_time, 0, sub {
                undef $tw;
                $d->done($target);
            };
        }
    );
    my $got_order_ref = [];
    {
        my $cv = Pseudo::CV->new;
        my $timeout; $timeout = EV::timer 10, 0, sub {
            undef $timeout;
            fail("timeout");
            $cv->send;
        };
        foreach my $order (1 .. $try_count) {
            $cv->begin();
            $filter->run(
                sub {
                    my ($filter_result) = @_;
                    push(@$got_order_ref, $filter_result);
                    $filter_done_count++;
                    $parallel_count--;
                    cmp_ok($parallel_count, ">=", 0, "Parallel count >= 0");
                    $cv->end();
                }, $order
            );
        }
        $cv->recv;
        undef $timeout;
    }
    note("Got orders: " . join(",", @$got_order_ref));
    cmp_ok($filter_done_count, "==", $try_count, "filter done count == $try_count");
    cmp_ok($got_max_parallel, "==", $expect_max_parallel, "max parallel == $expect_max_parallel");
    if(defined($expect_order_ref)) {
        cmp_ok(int(@$got_order_ref), "==", int(@$expect_order_ref), "size of got_order_ref is correct");
        is_deeply($got_order_ref, $expect_order_ref, "got_order_ref is deeply correct");
    }
}

{
        my $filter = BusyBird::Defer::Queue->new();
        &checkFilter($filter, [0..10], [0..10]);

        $filter->do(&filterPlus(5));
        &checkFilter($filter, [0..10], [5..15]);

        $filter->do(&filterReverse());
        &checkFilter($filter, [0..10], [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5]);

        ## my $child = $filter;
        ## $filter = BusyBird::Defer::Queue->new();
        ## $filter->do($child);
        ## &checkFilter($filter, [0..10], [8..18]);
        
        $filter->do(&filterPlus(3));
        $filter->do(&filterReverse());
        $filter->do(&filterSleepPush(2, 0.4));
        $filter->do(&filterSleepPush(100, 0.2));
        $filter->do(&filterSleepPush(300, 0.1));
        &checkFilter($filter, [0..10], [8..18, 2, 100, 300]);
}

{
    note("--- nested filters");
    my $granpa = BusyBird::Defer::Queue->new();
    my $dad    = BusyBird::Defer::Queue->new();
    my $son    = BusyBird::Defer::Queue->new();
    my $bro    = BusyBird::Defer::Queue->new();
    $granpa->do(&filterPlus(2));
    $granpa->do($dad);
    $dad->do(
        &filterPlus(-3),
        &filterReverse(),
        &filterCheck([9, 8, 7, 6, 5, 4, 3, 2, 1, 0, -1]),
        $son
    );
    $son->do(&filterSleepPush(100, 0.1));
    $son->do(&filterPlus(1));
    $son->do(&filterCheck([10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 101]));
    $dad->do(&filterReverse());
    $dad->do(&filterSleepPush(200, 0.2));
    $dad->do($bro);
    $bro->do(&filterCheck([101, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 200]));
    $bro->do(&filterReverse());
    $bro->do(&filterPlus(-10));
    $bro->do(&filterSleepPush(300, 0.2));
    $granpa->do(&filterSleepPush(500, 0.1));

    &checkFilter($granpa, [0..10], [190, 0, -1, -2, -3, -4, -5, -6, -7, -8, -9, -10, 91, 300, 500]);
}

{
    note("--- filter callbacks must not raise exceptions.");
    my $filter = BusyBird::Defer::Queue->new();
    $filter->do(&filterPlus(5));
    $filter->do(&filterSleepPush(16, 0.1));
    $filter->do(&filterDying(2, "Die in place", 1));
    $filter->do(&filterPlus(5));
    $filter->do(&filterDying(3, "Die not in place", 0));
    $filter->do(&filterSleepPush(100, 0.1));
    &checkFilter($filter, [0..10], [15, 16, 17, 18, 19, 20, 21, 100]);
}

{
    note("--- filter parallelism control");
    &checkParallel(2, 6, 2);
    &checkParallel(1, 7, 1, [1 .. 7]);
    &checkParallel(0, 8, 8, [reverse(1 .. 8)]);
}

{
    note("--- No big deal if nothing is given to a filter");
    my %filters = map { $_ => BusyBird::Defer::Queue->new() } qw(empty_filter single_filter);
    my %expected_filter_counters = (
        empty_filter => 0,
        single_filter => 3,
    );
    my $filter_counter = 0;
    my $single_filter_cv;
    $filters{single_filter}->do(
        sub {
            my ($d, $data) = @_;
            my $tw; $tw = EV::timer 0.01, 0, sub {
                undef $tw;
                $filter_counter++;
                $single_filter_cv->end();
                $d->done($data);
            };
        }
    );
    foreach my $key (keys %filters) {
        my $callback_counter = 0;
        {
            my $cv = Pseudo::CV->new;
            my $timeout; $timeout = EV::timer 10, 0, sub {
                undef $timeout;
                fail("$key: timeout");
                $cv->send;
            };
            $single_filter_cv = $cv;
            my $filter = $filters{$key};
            $filter_counter = 0;
            if($key eq 'single_filter') {
                $cv->begin() foreach 1..3;
            }
            lives_ok {
                $filter->run();
            } "$key: no input, no callback";
            lives_ok {
                $filter->run(undef, 1);
            } "$key: no callback";
            lives_ok {
                $cv->begin();
                $filter->run(sub { $callback_counter++; $cv->end() }, undef);
            } "$key: no input";
            $cv->recv;
            undef $timeout;
        }
        cmp_ok($callback_counter, "==", 1, "1 callback execution");
        cmp_ok($filter_counter, '==', $expected_filter_counters{$key}, "$expected_filter_counters{$key} filter element execution.");
    }
}

{
    my $filter = BusyBird::Defer::Queue->new();
    note("--- What if I push some junks to a filter?");
    lives_ok {$filter->do(undef)} 'push(undef) is ignored.';
    ## lives_ok {$filter->unshift(undef)} 'unshift(undef) is ignored.';
    dies_ok {$filter->do(1)} 'Do not push a scalar';
    dies_ok {$filter->do([10, 20, 30])} 'Do not push an array ref of scalars';
    dies_ok {$filter->do({foo => 1, bar => 2})} 'Do not push a hash ref of scalar values';
}

done_testing();



