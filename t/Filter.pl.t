#!/usr/bin/perl -w

package BusyBird::Test::Fake::FilterElem;
use strict;
use warnings;

sub new {
    my $class = shift;
    return bless {}, $class;
}


package main;


use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('BusyBird::Test', qw(CV within));
    use_ok('BusyBird::Filter');
}

sub checkFilter {
    my ($filter, $input_seq, $expected_seq) = @_;
    my $cv = AnyEvent->condvar;
    $filter->execute($input_seq, sub { $cv->send($_[0]) });
    my $got_seq = $cv->recv();
    is_deeply($got_seq, $expected_seq);
}

sub filterPlus {
    my $add_amount = shift;
    return sub {
        my ($statuses, $cb) = @_;
        $_ += $add_amount foreach @$statuses;
        my $tw; $tw = AnyEvent->timer(
            after => 0.1,
            cb => sub {
                undef $tw;
                $cb->($statuses);
            }
        );
    };
}

sub filterReverse {
    return sub {
        my ($statuses, $cb) = @_;
        my $tw; $tw = AnyEvent->timer(
            after => 0.1,
            cb => sub {
                undef $tw;
                $cb->( [reverse(@$statuses)] );
            }
        );
    };
}

sub filterSleepPush {
    my ($pushval, $sleep) = @_;
    return sub {
        my ($in, $cb) = @_;
        diag(sprintf('filterSleepPush with pushval => %s, sleep => %s', $pushval, $sleep));
        my $tw; $tw = AnyEvent->timer(
            after => $sleep,
            cb => sub {
                undef $tw;
                push(@$in, $pushval);
                $cb->($in);
            },
        );
    };
}

sub filterCheck {
    my ($expected_seq) = @_;
    return sub {
        my ($statuses, $cb) = @_;
        is_deeply($statuses, $expected_seq, "filterCheck");
        my $tw; $tw = AnyEvent->timer(
            after => 0.1,
            cb => sub {
                undef $tw;
                $cb->($statuses);
            },
        );
    }
}

sub filterDying {
    my ($add, $msg, $is_in_place) = @_;
    return sub {
        my ($statuses, $cb) = @_;
        my $tw; $tw = AnyEvent->timer(
            after => 0.2,
            cb => sub {
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
                    diag("filterDying dies: $@");
                }
                $cb->($is_in_place ? $statuses : \@new_statuses);
            }
        );
    };
}

sub checkParallel {
    my ($parallel_limit, $try_count, $expect_max_parallel, $expect_order_ref) = @_;
    diag("--- -- checkParallel limit => $parallel_limit, try_count => $try_count, expect_max_parallel => $expect_max_parallel");
    my $filter = BusyBird::Filter->new(parallel_limit => $parallel_limit);
    $expect_max_parallel ||= $parallel_limit;
    my $parallel_count = 0;
    my $filter_done_count = 0;
    my $got_max_parallel = 0;
    $filter->push(
        sub {
            my ($target, $cb) = @_;
            my $tw; $tw = AnyEvent->timer(
                after => 0,
                cb => sub {
                    undef $tw;
                    $parallel_count++;
                    if($parallel_limit > 0) {
                        cmp_ok($parallel_count, '<=', $parallel_limit, "Parallel count <= $parallel_limit");
                    }
                    $got_max_parallel = $parallel_count if $parallel_count > $got_max_parallel;
                    $cb->($target);
                }
            );
        }
    );
    $filter->push(
        sub {
            my ($target, $cb) = @_;
            ## ** descending amount of sleep_time
            my $sleep_time = 3.0 / $target;
            my $tw; $tw = AnyEvent->timer(
                after => $sleep_time,
                cb => sub {
                    undef $tw;
                    $cb->($target);
                }
            );
        }
    );
    my $got_order_ref = [];
    within 10, sub {
        foreach my $order (1 .. $try_count) {
            CV()->begin();
            $filter->execute(
                $order, sub {
                    my ($filter_result) = @_;
                    push(@$got_order_ref, $filter_result);
                    $filter_done_count++;
                    $parallel_count--;
                    cmp_ok($parallel_count, ">=", 0, "Parallel count >= 0");
                    CV()->end();
                }
            );
        }
    };
    diag("Got orders: " . join(",", @$got_order_ref));
    cmp_ok($filter_done_count, "==", $try_count, "filter done count == $try_count");
    cmp_ok($got_max_parallel, "==", $expect_max_parallel, "max parallel == $expect_max_parallel");
    if(defined($expect_order_ref)) {
        cmp_ok(int(@$got_order_ref), "==", int(@$expect_order_ref), "size of got_order_ref is correct");
        is_deeply($got_order_ref, $expect_order_ref, "got_order_ref is deeply correct");
    }
}

{
    my $filter = BusyBird::Filter->new();
    &checkFilter($filter, [0..10], [0..10]);

    $filter->push(&filterPlus(5));
    &checkFilter($filter, [0..10], [5..15]);

    $filter->push(&filterReverse());
    &checkFilter($filter, [0..10], [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5]);

    $filter->unshift(&filterReverse());
    $filter->unshift(&filterPlus(3));
    &checkFilter($filter, [0..10], [8..18]);

    $filter->push(&filterSleepPush(100, 2));
    $filter->push(&filterSleepPush(300, 1));
    $filter->unshift(&filterSleepPush(2, 4));
    &checkFilter($filter, [0..10], [8..18, 10, 100, 300]);
}

{
    diag("--- nested filters");
    my $granpa = BusyBird::Filter->new();
    my $dad    = BusyBird::Filter->new();
    my $son    = BusyBird::Filter->new();
    my $bro    = BusyBird::Filter->new();
    $granpa->push(&filterPlus(2));
    $granpa->push($dad);
    $dad->push(
        &filterPlus(-3),
        &filterReverse(),
        &filterCheck([9, 8, 7, 6, 5, 4, 3, 2, 1, 0, -1]),
        $son
    );
    $son->push(&filterSleepPush(100, 1));
    $son->push(&filterPlus(1));
    $son->push(&filterCheck([10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 101]));
    $dad->push(&filterReverse());
    $dad->push(&filterSleepPush(200, 2));
    $dad->push($bro);
    $bro->push(&filterCheck([101, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 200]));
    $bro->push(&filterReverse());
    $bro->push(&filterPlus(-10));
    $bro->push(&filterSleepPush(300, 2));
    $granpa->push(&filterSleepPush(500, 1));

    &checkFilter($granpa, [0..10], [190, 0, -1, -2, -3, -4, -5, -6, -7, -8, -9, -10, 91, 300, 500]);
}

{
    diag("--- filter callbacks must not raise exceptions.");
    diag("--- It is limitation of AnyEvent.");
    my $filter = BusyBird::Filter->new();
    $filter->push(&filterPlus(5));
    $filter->push(&filterSleepPush(16, 1));
    $filter->push(&filterDying(2, "Die in place", 1));
    $filter->push(&filterPlus(5));
    $filter->push(&filterDying(3, "Die not in place", 0));
    $filter->push(&filterSleepPush(100, 1));
    &checkFilter($filter, [0..10], [15, 16, 17, 18, 19, 20, 21, 100]);
}

{
    diag("--- filter parallelism control");
    &checkParallel(2, 6, 2);
    &checkParallel(1, 7, 1, [1 .. 7]);
    &checkParallel(0, 8, 8, [reverse(1 .. 8)]);
}

{
    my $filter = BusyBird::Filter->new();
    diag("--- What if I pushed some junks to a filter?");
    dies_ok {$filter->push(undef)} 'Do not push undef';
    dies_ok {$filter->unshift(undef)} 'Do not unshift undef';
    dies_ok {$filter->push(1)} 'Do not push a scalar';
    dies_ok {$filter->push([10, 20, 30])} 'Do not push an array ref';
    dies_ok {$filter->push({foo => 1, bar => 2})} 'Do not push a hash ref';
    my $fake_elem = new_ok('BusyBird::Test::Fake::FilterElem');
    dies_ok {$filter->push($fake_elem)} 'Do not push an object that is not provide filterElement';
}

done_testing();



