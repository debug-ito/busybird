#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;
use Test::AnyEvent::Time;

BEGIN {
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('BusyBird::Timer');
}

sub testTimer {
    my (%params) = @_;
    note("--- testTimer(" . join(", ", map { "$_ => $params{$_}" } keys %params) . ")");
    my $timer = new_ok('BusyBird::Timer', [%params]);
    my $counter = 0;

    my $timer_cv;
    $timer->addOnFire(
        sub {
            $counter++;
            note("counter: $counter");
            $timer_cv->end();
        }
    );

    time_within_ok sub {
        my $cv = shift;
        $timer_cv = $cv;
        $cv->begin() foreach 1..5;
    }, 10;
    cmp_ok($counter, "==", 5);

    my $another_counter = 0;
    $timer->addOnFire(
        sub {
            $another_counter++;
            note("another: $another_counter");
            $timer_cv->end();
        }
    );

    time_within_ok sub {
        my $cv = shift;
        $timer_cv = $cv;
        $cv->begin() foreach 1..10;
    }, 10;
    cmp_ok($counter, "==", 10);
    cmp_ok($another_counter, "==", 5);
    $timer->stop();
}

testTimer interval => 0.2;
testTimer after => 0, interval => 1;
testTimer after => 0.3, interval => 1, callback_interval => 0.1;
testTimer after => 0.5, interval => 0.1, callback_interval => 0.6;


done_testing();




