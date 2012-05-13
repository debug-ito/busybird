#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('BusyBird::Timer');
    use_ok('BusyBird::Test', qw(CV within));
}

sub testTimer {
    my (%params) = @_;
    note("--- testTimer(" . join(", ", map { "$_ => $params{$_}" } keys %params) . ")");
    my $timer = new_ok('BusyBird::Timer', [%params]);
    my $counter = 0;

    $timer->addOnFire(
        sub {
            $counter++;
            note("counter: $counter");
            CV()->end();
        }
    );

    within 10, sub {
        CV()->begin() foreach 1..5;
    };
    cmp_ok($counter, "==", 5);

    my $another_counter = 0;
    $timer->addOnFire(
        sub {
            $another_counter++;
            note("another: $another_counter");
            CV()->end();
        }
    );

    within 10, sub {
        CV()->begin() foreach 1..10;
    };
    cmp_ok($counter, "==", 10);
    cmp_ok($another_counter, "==", 5);
    $timer->stop();
}

testTimer interval => 0.2;
testTimer after => 0, interval => 1;
testTimer after => 0.3, interval => 1, callback_interval => 0.1;
testTimer after => 0.5, interval => 0.1, callback_interval => 0.6;


done_testing();




