use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('App::BusyBird::Log');
}

my $logger = App::BusyBird::Log->logger();
isa_ok($logger, 'App::BusyBird::Log');
can_ok($logger, "log");

done_testing();
