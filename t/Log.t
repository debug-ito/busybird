use strict;
use warnings;

use Test::More;
use Test::Warn;

BEGIN {
    use_ok('App::BusyBird::Log');
}

{
    local $App::BusyBird::Log::LOGGER = undef;
    warning_is { bblog('error', 'log is suppressed') } undef, 'Log is suppressed.';
}


my $log = "";

$App::BusyBird::Log::LOGGER = sub {
    my ($level, $msg) = @_;
    $log .= "$level: $msg\n";
};

bblog("notice", "log test");
is($log, "notice: log test\n", "log OK");

{
    my @logs = ();
    local $App::BusyBird::Log::LOGGER = sub {
        my ($level, $msg) = @_;
        push(@logs, [$level, $msg]);
    };
    bblog("warn", "warning test");
    is($log, "notice: log test\n", '$log is not changed.');
    is_deeply(@logs, ['warn', 'warning test'], 'logged to @logs');
}

bblog('info', 'end log');
is($log, "notice: log test\ninfo: end log\n", "LOGGER is restored.");

done_testing();
