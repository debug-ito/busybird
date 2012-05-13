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

my $timer = new_ok('BusyBird::Timer', [interval => 1]);
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

done_testing();









