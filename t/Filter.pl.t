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
    return sub { $_ += $add_amount foreach @{$_[0]}; $_[1]->($_[0]) };
}

sub filterReverse {
    return sub { $_[1]->( [ reverse(@{$_[0]}) ] ) };
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

my $filter = BusyBird::Filter->new();
&checkFilter($filter, [0..10], [0..10]);

$filter->push(&filterPlus(5));
&checkFilter($filter, [0..10], [5..15]);

$filter->push(&filterReverse());
&checkFilter($filter, [0..10], [15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5]);

$filter->unshift(&filterReverse());
$filter->unshift(&filterPlus(3));
&checkFilter($filter, [0..10], [8..18]);

$filter->push(&filterSleepPush(100, 5));
$filter->push(&filterSleepPush(300, 2));
$filter->unshift(&filterSleepPush(2, 10));
&checkFilter($filter, [0..10], [8..18, 10, 100, 300]);


done_testing();



