use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('App::BusyBird::Log');
}

my $logger_obj = App::BusyBird::Log->logger_obj();
isa_ok($logger_obj, 'App::BusyBird::Log');
can_ok($logger_obj, "log");
is(ref(App::BusyBird::Log->logger), "CODE", "logger is coderef");

done_testing();
