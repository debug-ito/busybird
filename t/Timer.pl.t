#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('BusyBird::Timer');
}

my $timer = new_ok('BusyBird::Timer', [interval => 1]);
my $counter = 0;
my $cv = AnyEvent->condvar;

$timer->addOnFire(
    sub {
        $counter++;
        diag("counter: $counter");
        if($counter >= 5) {
            $cv->send();
        }
    });

$cv->recv();
cmp_ok($counter, "==", 5);

my $another_cv = AnyEvent->condvar;
my $another_counter = 0;
$timer->addOnFire(
    sub {
        $another_counter++;
        diag("another: $another_counter");
        if($another_counter >= 5) {
            $another_cv->send();
        }
    }
);

$another_cv->recv();
cmp_ok($counter, "==", 10);
cmp_ok($another_counter, "==", 5);

done_testing();









