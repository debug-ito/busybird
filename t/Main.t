use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Memory::Cycle;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use BusyBird::Test::Timeline_Util qw(status sync);
use BusyBird::Test::StatusStorage qw(:status);
use BusyBird::StatusStorage::Memory;
use BusyBird::Timeline;
use BusyBird::Log;

BEGIN {
    use_ok('BusyBird::Main');
}

$BusyBird::Log::LOGGER = undef;

our $CREATE_STORAGE = sub {
    return BusyBird::StatusStorage::Memory->new;
};

sub test_watcher_basic {
    my ($watcher) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    isa_ok($watcher, 'BusyBird::Watcher');
    can_ok($watcher, 'active', 'cancel');
}


{
    my $main = new_ok('BusyBird::Main');
    my $storage = $CREATE_STORAGE->();
    $main->default_status_storage($storage);
    is($main->default_status_storage, $storage, 'setting default_status_storage OK');
    is_deeply([$main->get_all_timelines], [], 'at first, no timelines');

    my $tl1 = $main->timeline('test1');
    isa_ok($tl1, 'BusyBird::Timeline', 'timeline() creates a timeline');
    is($tl1->name, 'test1', "... its name is test1");
    is_deeply([$main->get_all_timelines], [$tl1], 'test1 is installed,.');
    is($main->timeline('test1'), $tl1, 'timeline() returns the installed timeline');
    is($main->get_timeline('test1'), $tl1, 'get_timeline() returns the installed timeline');

    is($main->get_timeline('foobar'), undef, 'get_timeline() returns undef if the timeline is not installed.');
    my $tl2 = BusyBird::Timeline->new(name => 'foobar', storage => $CREATE_STORAGE->());
    $main->install_timeline($tl2);
    is($main->get_timeline('foobar'), $tl2, 'install_timeline() installs a timeline');
    is($main->timeline('foobar'), $tl2, 'timeline() returns the installed timeline');
    is_deeply([$main->get_all_timelines], [$tl1, $tl2], "get_all_timelines() return the two timelines");

    is($main->uninstall_timeline('hogehoge'), undef, 'uninstall_timeline() returns undef it the timeline is not installed');
    is($main->uninstall_timeline('test1'), $tl1, 'uninstall test1 timeline');
    is($main->get_timeline('test1'), undef, 'now test1 is not installed');
    is_deeply([$main->get_all_timelines], [$tl2], 'now only foobar is installed.');

    my $tl3 = BusyBird::Timeline->new(name => 'foobar', storage => $CREATE_STORAGE->());
    $main->install_timeline($tl3);
    is($main->get_timeline('foobar'), $tl3, 'install_timeline() replaces the old timeline with the same name');
    is($main->timeline('foobar'), $tl3, 'timeline() returns the installed timeline');
}

{
    my $main = BusyBird::Main->new();
    $main->default_status_storage($CREATE_STORAGE->());
    $main->timeline($_) foreach reverse 1..20;
    is_deeply(
        [map { $_->name } $main->get_all_timelines],
        [reverse 1..20],
        'order of timelines from get_all_timelines() is preserved.'
    );
}

{
    my $main = BusyBird::Main->new();
    $main->default_status_storage($CREATE_STORAGE->());
    my $storage1 = $main->default_status_storage();
    my $storage2 = $CREATE_STORAGE->();

    my $tl1 = $main->timeline('1');
    is($main->default_status_storage($storage2), $storage2, 'default_status_storage() setter returns the changed setting.');
    my $tl2 = $main->timeline('2');
    sync($tl1, 'add_statuses', statuses => [status(10)]);
    sync($tl2, 'add_statuses', statuses => [status(20)]);
    my $error;
    ($error, my ($s11)) = sync($storage1, 'get_statuses', timeline => 1, count => 'all');
    ($error, my ($s12)) = sync($storage1, 'get_statuses', timeline => 2, count => 'all');
    ($error, my ($s21)) = sync($storage2, 'get_statuses', timeline => 1, count => 'all');
    ($error, my ($s22)) = sync($storage2, 'get_statuses', timeline => 2, count => 'all');
    test_status_id_set($s11, [10], 'status 10 is saved to storage 1');
    test_status_id_set($s12, [],   'no status in timeline 2 is saved to storage 1');
    test_status_id_set($s21, [],   'no status in timeline 1 is saved to storage 2');
    test_status_id_set($s22, [20], 'status 20 is saved to storage 2');
}

{
    my $main = BusyBird::Main->new();
    $main->default_status_storage($CREATE_STORAGE->());
    my $app = $main->to_app();
    is(ref($app), 'CODE', 'to_app() returns a coderef');
    my @timelines = $main->get_all_timelines();
    is(int(@timelines), 1, 'when no timeline is configured, to_app() generates one.');
    is($timelines[0]->name, 'home', '... the timeline is named "home"');

    $main = BusyBird::Main->new();
    $main->default_status_storage($CREATE_STORAGE->());
    my $tl = $main->timeline('hoge');
    $app = $main->to_app();
    is(ref($app), 'CODE', 'to_app() returns a coderef');
    @timelines = $main->get_all_timelines();
    is_deeply(\@timelines, [$tl], 'If the main has a timeline, "home" timeline is not created by to_app()');
}

{
    note('--- -- watch_unacked_counts');
    my $main = BusyBird::Main->new();
    memory_cycle_ok($main, 'no cyclic ref in main');
    $main->default_status_storage($CREATE_STORAGE->());
    $main->timeline('a');
    sync($main->timeline('b'), 'add_statuses', statuses => [status(1), status(2, 2)]);
    sync($main->timeline('c'), 'add_statuses', statuses => [status(3, -3), status(4,0), status(5)]);
    sync($main->timeline('a'), 'get_statuses', count => 1); ## go into event loop
    note('--- watch immediate');
    my %exp_counts = (
        a => {total => 0},
        b => {total => 2, 0 => 1, 2 => 1},
        c => {total => 3, 0 => 2, -3 => 1}
    );
    foreach my $case (
        {label => "total a", watch => {level => 'total', assumed => {a => 0}}, exp_callback => 0},
        {label => "total a,b,c", watch => {level => 'total', assumed => {a => 0, b => 0, c => 0}}, exp_callback => 1},
        {label => "level omitted callbacked", watch => {assumed => {c => 2}}, exp_callback => 1, exp_tls => ['c']},
        {label => "level omitted not callbacked", watch => {assumed => {c => 3}}, exp_callback => 0},
        {label => "lv.0 correct", watch => {level => 0, assumed => {b => 1, c => 2}}, exp_callback => 0},
        {label => "lv.0 wrong", watch => {level => 0, assumed => {b => 1, c => 1}}, exp_callback => 1, exp_tls => ['c']},
        {label => "lv.2 correct", watch => {level => 2, assumed => {a => 0, b => 1, c => 0}}, exp_callback => 0},
        {label => "lv.2 wrong", watch => {level => 2, assumed => {a => 4, c => 0}}, exp_callback => 1, exp_tls => ['a']},
        {label => "lv.-1 correct", watch => {level => -1, assumed => {b => 0, c => 0}}, exp_callback => 0},
        {label => "lv.-3 correct", watch => {level => -3, assumed => {a => 0, c => 1}}, exp_callback => 0},
        {label => "lv.-3 wrong", watch => {level => -3, assumed => {b => 4, c => 0}}, exp_callback => 1},
        {label => "junk level", watch => {level => 'junk', assumed => {a => 0, b => 0}}, exp_callback => 1}
    ) {
        my $label = defined($case->{label}) ? $case->{label} : "";
        my $callbacked = 0;
        my $inside_w;
        my $watcher = $main->watch_unacked_counts(%{$case->{watch}}, callback => sub {
            my ($error, $w, $got_counts) = @_;
            $callbacked = 1;
            is($error, undef, "$label: watch_unacked_counts succeed");
            my @keys = keys %$got_counts;
            cmp_ok(int(@keys), ">=", 1, "$label: at least 1 key obtained.");
            if(defined($case->{exp_tls})) {
                foreach my $exp_tl (@{$case->{exp_tls}}) {
                    ok(defined($got_counts->{$exp_tl}), "timeline $exp_tl is included in result");
                }
            }
            foreach my $key (@keys) {
                is_deeply($got_counts->{$key}, $exp_counts{$key}, "$label: unacked counts for $key OK");
            }
            $w->cancel();
            $inside_w = $w;
        });
        test_watcher_basic($watcher);
        memory_cycle_ok($main, "$label: no cyclic ref in main");
        memory_cycle_ok($watcher, "$label: no cyclic ref in watcher");
        is($callbacked, $case->{exp_callback}, "callbacked is $case->{exp_callback}");
        if($callbacked) {
            is($inside_w, $watcher, "$label: watcher inside is the same as the watcher outside");
        }
        $watcher->cancel();
    }

    {
        note('--- watch persistent and delayed');
        my %results;
        my $callbacked;
        my $reset = sub {
            %results = (a => [], b => [], c => []);
            $callbacked = 0;
        };
        my $callback_func = sub {
            my ($error, $w, $unacked_counts) = @_;
            is($error, undef, 'watch_unacked_counts succeed');
            push(@{$results{$_}}, $unacked_counts->{$_}) foreach keys %$unacked_counts;
            $callbacked++;
        };
        $reset->();
        my $watcher = $main->watch_unacked_counts(
            level => 'total', assumed => {a => 0, b => 2, c => 3}, callback => $callback_func
        );
        memory_cycle_ok($main, "no cyclic ref in main");
        memory_cycle_ok($watcher, 'no cyclic ref in watcher');
        sync($main->timeline('b'), 'ack_statuses');
        sync($main->timeline('c'), 'delete_statuses', ids => [4]);
        sync($main->timeline('a'), 'add_statuses', statuses => [status(6, 1)]);
        sync($main->timeline('a'), 'get_statuses', count => 1); ## go into event loop
        is($callbacked, 3, "3 callbacked");
        is_deeply(\%results, {a => [{total => 1, 1 => 1}], b => [{total => 0}], c => [{total => 2, 0 => 1, -3 => 1}]},
                  "results OK");
        $watcher->cancel();

        $reset->();
        $watcher = $main->watch_unacked_counts(1, {a => 1, b => 0, c => 1}, $callback_func);
        sync($main->timeline('b'), 'put_statuses', mode => 'insert', statuses => [status(7, 1)]);
        sync($main->timeline('c'), 'put_statuses', mode => 'update', statuses => [status(3, 1)]);
        sync($main->timeline('a'), 'put_statuses', mode => 'update', statuses => [status(6)]);
        sync($main->timeline('a'), 'get_statuses', count => 1); ## go into event loop
        is($callbacked, 3, '3 callbacked');
        is_deeply(\%results, {a => [{total => 1, 0 => 1}], b => [{total => 1, 1 => 1}], c => [{total => 2, 0 => 1, -3 => 1}]},
                  "results OK");
        $watcher->cancel();
    }
}

{
    note('--- watch_unacked_counts: junk input');
    my $main = BusyBird::Main->new();
    $main->default_status_storage($CREATE_STORAGE->());
    $main->timeline('a');
    my %a = (assumed => {a => 1});
    foreach my $case (
        {label => 'empty assumed', args => {level => 'total', assumed => {}, callback => sub {}}},
        {label => 'watching only unknown timeline', args => {level => 'total', assumed => {b => 1}, callback => sub {}}},
        {label => 'assumed str', args => {assumed => 'hoge', callback => sub {}}},
        {label => 'no assumed', args => {callback => sub {}}},
        {label => 'assumed undef', args => {assumed => undef, callback => sub {}}},
        {label => "assumed array-ref", args => {assumed => [], callback => sub {}}},
        {label => "assumed code-ref", args => {assumed => sub {}, callback => sub {}}},
        {label => 'no callback', args => {%a}},
        {label => 'callback undef', args => {%a, callback => undef}},
        {label => 'callback str', args => {%a, callback => 'foobar'}},
        {label => 'callback array-ref', args => {%a, callback => []}},
        {label => 'callback hash-ref', args => {%a, callback => {}}},
    ) {
        dies_ok { $main->watch_unacked_counts(%{$case->{args}}) } "watch_unacked_counts: $case->{label}: raises an exception";
    }
    my $w;
    lives_ok { $w = $main->watch_unacked_counts(assumed => {a => 0, b => 0}, callback => sub {}) } 'unknown timeline is ignored.';
    ok($w->active, 'watcher is active.');
    $w->cancel();
}

done_testing();
