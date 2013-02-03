use strict;
use warnings;
use Test::More;
use Test::Memory::Cycle;

BEGIN {
    use_ok('App::BusyBird::Flow');
}

my $flow = App::BusyBird::Flow->new();
memory_cycle_ok($flow);

done_testing();


