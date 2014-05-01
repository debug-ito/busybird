use strict;
use warnings;
use Test::More;
use BusyBird::Main;
use BusyBird::Log;
use BusyBird::StatusStorage::SQLite;

BEGIN {
    use_ok("BusyBird::Main::PSGI", "create_psgi_app");
}

$BusyBird::Log::Logger = undef;

sub create_main {
    my $main = BusyBird::Main->new;
    $main->set_config(default_status_storage => BusyBird::StatusStorage::SQLite->new(path => ':memory:'));
    return $main;
}

{
    my $main = create_main();
    my $app = create_psgi_app($main);
    is(ref($app), 'CODE', 'create_psgi_app() returns a coderef');
    my @timelines = $main->get_all_timelines();
    is(int(@timelines), 0, 'app can be created without any timeline.');

    $main = create_main();
    my $tl = $main->timeline('hoge');
    $app = create_psgi_app($main);
    is(ref($app), 'CODE', 'create_psgi_app() returns a coderef');
    @timelines = $main->get_all_timelines();
    is_deeply(\@timelines, [$tl], 'app is created with a timeline.');
}

done_testing();
