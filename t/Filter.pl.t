#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
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
    $granpa->pushFilters($dad);
    $dad->push(&filterPlus(-3));
    $dad->push(&filterReverse());
    $dad->push(&filterCheck([9, 8, 7, 6, 5, 4, 3, 2, 1, 0, -1]));
    $dad->pushFilters($son);
    $son->push(&filterSleepPush(100, 1));
    $son->push(&filterPlus(1));
    $son->push(&filterCheck([10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 101]));
    $dad->push(&filterReverse());
    $dad->push(&filterSleepPush(200, 2));
    $dad->pushFilters($bro);
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
    fail("test must be written");
}

done_testing();



