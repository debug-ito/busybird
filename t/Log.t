use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('App::BusyBird::Log');
}

is(ref(App::BusyBird::Log->logger), "CODE", "logger is coderef");

my @log = ();
my $logger = sub {
    push(@log, @_);
};
is(App::BusyBird::Log->logger($logger), $logger, "logger set");
App::BusyBird::Log->logger->("info", "information");
is_deeply(\@log, ['info', 'information'], "logged");

done_testing();
