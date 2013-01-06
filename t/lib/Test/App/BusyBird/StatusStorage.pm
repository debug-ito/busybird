package Test::App::BusyBird::StatusStorage;
use strict;
use warnings;
use Exporter qw(import);
use DateTime;
use DateTime::Duration;
use Test::More;
use Test::Builder;
use App::BusyBird::DateTime::Format;
use Carp;

our @EXPORT = qw(test_status_storage test_status_order);

my $datetime_formatter = 'App::BusyBird::DateTime::Format';

sub status {
    my ($id, $level, $confirmed_at) = @_;
    croak "you must specify id" if not defined $id;
    my $status = {
        id => $id,
        created_at => $datetime_formatter->format_datetime(
            DateTime->from_epoch(epoch => $id)
        ),
    };
    $status->{busybird}{level} = $level if defined $level;
    $status->{busybird}{confirmed_at} = $confirmed_at if defined $confirmed_at;
    return $status;
}

sub nowstring {
    return $datetime_formatter->format_datetime(
        DateTime->now(time_zone => 'UTC')
    );
}

sub id_counts {
    my @statuses_or_ids = @_;
    my %id_counts = ();
    foreach my $s_id (@statuses_or_ids) {
        my $id = ref($s_id) ? $s_id->{id} : $s_id;
        $id_counts{$id} += 1;
    }
    return %id_counts;
}

sub id_list {
    my @statuses_or_ids = @_;
    return map { ref($_) ? $_->{id} : $_ } @statuses_or_ids;
}

sub confirmed {
    my ($s) = @_;
    no autovivification;
    return $s->{busybird}{confirmed_at};
}

sub test_status_id_set {
    ## unordered status ID set test
    my ($got_statuses, $exp_statuses_or_ids, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    return is_deeply(
        { id_counts @$got_statuses },
        { id_counts @$exp_statuses_or_ids },
        $msg
    );
}

sub test_status_id_list {
    ## ordered status ID list test
    my ($got_statuses, $exp_statuses_or_ids, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    return is_deeply(
        [id_list @$got_statuses],
        [id_list @$exp_statuses_or_ids],
        $msg
    );
}

sub sync_get {
    my ($storage, $loop, $unloop, %query) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $callbacked = 0;
    my $statuses;
    $storage->get_statuses(%query, callback => sub {
        is(int(@_), 1, 'operation succeed');
        $statuses = $_[0];
        $callbacked = 1;
        $unloop->();
    });
    $loop->();
    ok($callbacked, 'callbacked');
    return $statuses;
}

sub on_statuses {
    my ($storage, $loop, $unloop, $query_ref, $code) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    $code->(sync_get($storage, $loop, $unloop, %$query_ref));
}

sub change_and_check {
    my ($storage, $loop, $unloop, %args) = @_;
    my $callbacked = 0;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $label = "change_and_check " . ($args{label} || "") . ":";
    my $callback_func = sub {
        my ($result) = @_;
        is(int(@_), 1, "$label $args{mode} succeed.");
        is($result, $args{exp_change},
           "$label $args{mode} changed $args{exp_change}");
        $callbacked = 1;
        $unloop->();
    };
    if($args{mode} eq 'insert' || $args{mode} eq 'update' || $args{mode} eq 'upsert') {
        $storage->put_statuses(
            timeline => $args{timeline},
            mode => $args{mode},
            statuses => $args{target},
            callback => $callback_func,
        );
        $loop->();
    }elsif($args{mode} eq 'delete' || $args{mode} eq 'confirm') {
        my $method = "$args{mode}_statuses";
        $storage->$method(
            timeline => $args{timeline},
            ids => $args{target},
            callback => $callback_func,
        );
        $loop->();
    }else {
        croak "Invalid mode";
    }
    on_statuses $storage, $loop, $unloop, {
        timeline => $args{timeline}, count => 'all',
        confirm_state => 'confirmed'
    }, sub {
        my $statuses = shift;
        test_status_id_set(
            $statuses, $args{exp_confirmed},
            "$label confirmed statuses OK"
        );
        foreach my $s (@$statuses) {
            ok(confirmed($s), "$label confirmed");
        }
    };
    on_statuses $storage, $loop, $unloop, {
        timeline => $args{timeline}, count => 'all',
        confirm_state => 'unconfirmed',
    }, sub {
        my $statuses = shift;
        test_status_id_set(
            $statuses, $args{exp_unconfirmed},
            "$label unconfirmed statuses OK"
        );
        foreach my $s (@$statuses) {
            ok(!confirmed($s), "$label not confirmed");
        }
    };
    on_statuses $storage, $loop, $unloop, {
        timeline => $args{timeline}, count => 'all',
        confirm_state => 'any',
    }, sub {
        my $statuses = shift;
        test_status_id_set(
            $statuses, [@{$args{exp_confirmed}}, @{$args{exp_unconfirmed}}],
            "$label statuses in any state OK"
        );
    };
}

sub get_and_check_list {
    my ($storage, $loop, $unloop, $get_args, $exp_id_list, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    on_statuses $storage, $loop, $unloop, $get_args, sub {
        my $statuses = shift;
        test_status_id_list $statuses, $exp_id_list, $msg;
    };
}


sub test_status_storage {
    my ($storage, $loop, $unloop) = @_;
    $loop ||= sub {};
    $unloop ||= sub {};
    my $callbacked = 0;
    note("--- clear the timelines");
    foreach my $tl ('_test_tl1', "_test  tl2") {
        $callbacked = 0;
        $storage->delete_statuses(
            timeline => $tl,
            callback => sub {
                $callbacked = 1;
                $unloop->();
            }
        );
        $loop->();
        ok($callbacked, "callbacked");
        is_deeply(
            { $storage->get_unconfirmed_counts(timeline => $tl) },
            { total => 0 },
            "$tl is empty"
        );
    }
    
    note("--- put_statuses (insert), single");
    $callbacked = 0;
    $storage->put_statuses(
        timeline => '_test_tl1',
        mode => 'insert',
        statuses => status(1),
        callback => sub {
            my ($num, $error) = @_;
            is(int(@_), 1, 'put_statuses succeed.');
            is($num, 1, 'put 1 status');
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    is_deeply(
        { $storage->get_unconfirmed_counts(timeline => '_test_tl1') },
        { total => 1, 0 => 1 },
        '1 unconfirmed status'
    );
    note('--- put_statuses (insert), multiple');
    $callbacked = 0;
    $storage->put_statuses(
        timeline => '_test_tl1',
        mode => 'insert',
        statuses => [map { status($_) } 2..5],
        callback => sub {
            my ($num, $error) = @_;
            is(int(@_), 1, 'put_statuses succeed');
            is($num, 4, 'put 4 statuses');
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    is_deeply(
        { $storage->get_unconfirmed_counts(timeline => '_test_tl1') },
        { total => 5, 0 => 5 },
        '5 unconfirmed status'
    );

    note('--- get_statuses: any, all');
    $callbacked = 0;
    $storage->get_statuses(
        timeline => '_test_tl1',
        count => 'all',
        callback => sub {
            my ($statuses, $error) = @_;
            is(int(@_), 1, "get_statuses succeed");
            test_status_id_set($statuses, [1..5], "1..5 statuses");
            foreach my $s (@$statuses) {
                no autovivification;
                ok(!$s->{busybird}{confirmed_at}, "status is not confirmed");
            }
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");

    note('--- confirm_statuses: all');
    $callbacked = 0;
    $storage->confirm_statuses(
        timeline => '_test_tl1',
        callback => sub {
            my ($num, $error) = @_;
            is(int(@_), 1, "confirm_statuses succeed");
            is($num, 5, "5 statuses confirmed.");
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    is_deeply(
        { $storage->get_unconfirmed_counts(timeline => '_test_tl1') },
        { total => 0 },
        "all confirmed"
    );
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl1', count => 'all'
    }, sub {
        my $statuses = shift;
        is(int(@$statuses), 5, "5 statueses");
        foreach my $s (@$statuses) {
            no autovivification;
            ok($s->{busybird}{confirmed_at}, 'confirmed');
        }
    };

    note('--- delete_statuses (single deletion)');
    $callbacked = 0;
    $storage->delete_statuses(
        timeline => '_test_tl1',
        ids => 3,
        callback => sub {
            my ($num, $error) = @_;
            is(int(@_), 1, "operation succeed.");
            is($num, 1, "1 deletion");
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl1', count => 'all'
    }, sub {
        my $statuses = shift;
        test_status_id_set($statuses, [1,2,4,5], "ID=3 is deleted");
    };

    note('--- delete_statuses (multiple deletion)');
    $callbacked = 0;
    $storage->delete_statuses(
        timeline => '_test_tl1',
        ids => [1, 4],
        callback => sub {
            my ($num, $error) = @_;
            is(int(@_), 1, 'operation succeed');
            is($num, 2, "2 statuses deleted");
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl1', count => 'all'
    }, sub {
        my $statuses = shift;
        test_status_id_set($statuses, [2,5], "ID=1,4 are deleted");
    };

    note('--- delete_statuses (all deletion)');
    $callbacked = 0;
    $storage->delete_statuses(
        timeline => '_test_tl1',
        ids => undef,
        callback => sub {
            my ($num, $error) = @_;
            is(int(@_), 1, 'operation succeed');
            is($num, 2, "2 statuses deleted");
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl1', count => 'all'
    }, sub {
        my $statuses = shift;
        test_status_id_set($statuses, [], "ID=2,5 are deleted. now empty");
    };

    note('--- put_statuses (insert): insert duplicate IDs');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'insert', target => [map { status $_ } (1,2,3,2,1,1,4,5,3)],
        exp_change => 5,
        exp_unconfirmed => [1..5], exp_confirmed => []
    );
    note('--- confirm_statuses: single confirmation');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'confirm', target => 3, exp_change => 1,
        exp_unconfirmed => [1,2,4,5], exp_confirmed => [3]
    );
    is_deeply(
        {$storage->get_unconfirmed_counts(timeline => '_test_tl1')},
        {total => 4, 0 => 4}, "4 unconfirmed statuses"
    );
    note('--- confirm_statuses: multiple partial confirmation');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'confirm', target => [1,5,3], exp_change => 3,
        exp_unconfirmed => [2,4], exp_confirmed => [1,3,5]
    );
    note('--- put (insert): try to insert existent status');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'insert', target => status(3), exp_change => 0,
        exp_unconfirmed => [2,4], exp_confirmed => [1,3,5]
    );
    note('--- put (update): change to unconfirmed');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'update', target => [map { status($_) } (3,5)],
        exp_change => 2, exp_unconfirmed => [2,3,4,5], exp_confirmed => [1]
    );
    is_deeply(
        {$storage->get_unconfirmed_counts(timeline => '_test_tl1')},
        {total => 4, 0 => 4}, '4 unconfirmed statuses'
    );
    note('--- put (update): change level');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'update',
        target => [map { status($_, ($_ % 2 + 1), $_ == 1 ? nowstring() : undef) } (1..5)],
        exp_change => 5, exp_unconfirmed => [2,3,4,5], exp_confirmed => [1]
    );
    is_deeply(
        {$storage->get_unconfirmed_counts(timeline => '_test_tl1')},
        {total => 4, 1 => 2, 2 => 2}, "4 unconfirmed statuses in 2 levels"
    );
    note('--- put (upsert): confirmed statuses');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'upsert', target => [map { status($_, 7, nowstring()) } (4..7)],
        exp_change => 4, exp_unconfirmed => [2,3], exp_confirmed => [1,4..7]
    );
    note('--- get and put(update): back to unconfirmed');
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl1', count => 'all', confirm_state => 'confirmed'
    }, sub {
        my $statuses = shift;
        delete $_->{busybird}{confirmed_at} foreach @$statuses;
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test_tl1',
            mode => 'update', target => $statuses,
            exp_change => 5, exp_unconfirmed => [1..7], exp_confirmed => []
        );
    };
    is_deeply(
        {$storage->get_unconfirmed_counts(timeline => '_test_tl1')},
        {total => 7, 1 => 1, 2 => 2, 7 => 4}, "3 levels"
    );

    note('--- put(insert): to another timeline');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test  tl2',
        mode => 'insert', target => [map { status($_) } (1..10)],
        exp_change => 10, exp_unconfirmed => [1..10], exp_confirmed => []
    );
    is_deeply(
        {$storage->get_unconfirmed_counts(timeline => '_test  tl2')},
        {total => 10, 0 => 10}, '10 unconfirmed statuses'
    );
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test  tl2',
        mode => 'confirm', target => [1..5],
        exp_change => 5, exp_unconfirmed => [6..10], exp_confirmed => [1..5]
    );
    note('--- get: single, any state');
    foreach my $id (1..10) {
        on_statuses $storage, $loop, $unloop, {
            timeline => '_test  tl2', count => 1, max_id => $id
        }, sub {
            my $statuses = shift;
            is(int(@$statuses), 1, "get 1 status");
            is($statuses->[0]{id}, $id, "... and its ID is $id");
        };
    }
    note('--- get: single, specific state');
    foreach my $id (1..10) {
        my $correct_state = ($id <= 5) ? 'confirmed' : 'unconfirmed';
        my $wrong_state = $correct_state eq 'confirmed' ? 'unconfirmed' : 'confirmed';
        on_statuses $storage, $loop, $unloop, {
            timeline => '_test  tl2', count => 1, max_id => $id,
            confirm_state => $correct_state,
        }, sub {
            my $statuses = shift;
            is(int(@$statuses), 1, "get 1 status");
            is($statuses->[0]{id}, $id, "... and its ID is $id");
        };
        foreach my $count ('all', 1, 10) {
            on_statuses $storage, $loop, $unloop, {
                timeline => '_test  tl2', count => $count, max_id => $id,
                confirm_state => $wrong_state
            }, sub {
                my $statuses = shift;
                is(int(@$statuses), 0,
                   "no status returned when status specified" . 
                       " max_id is not the correct confirm_state".
                           " even when count = $count");
            };    
        }
    }
    note('--- timeline is independent of each other');
    on_statuses $storage, $loop, $unloop, {
        timeline => "_test_tl1", count => "all"
    }, sub {
        my $statuses = shift;
        test_status_id_set($statuses, [1..7], "7 statuses in _test_tl1");
    };
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test  tl2', count => "all",
    }, sub {
        my $statuses = shift;
        test_status_id_set($statuses, [1..10], "10 statuses in _test  tl2");
    };
    note('--- access to non-existent statuses');
    foreach my $mode (qw(update delete confirm)) {
        my $target = $mode eq 'update'
            ? [map { status($_) } (11..15) ] : [11..15];
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test  tl2',
            mode => $mode, target => $target, label => "mode $mode",
            exp_change => 0, exp_unconfirmed => [6..10],
            exp_confirmed => [1..5]
        );
    }
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test  tl2', count => 'all', max_id => 15,
    }, sub {
        my $statuses = shift;
        is(int(@$statuses), 0, "get max_id=15 returns empty");
    };
    note('--- access to non-existent timeline');
    foreach my $mode (qw(update delete confirm)) {
        my $timeline = '_this_timeline_ probably does not exist';
        my $target = $mode eq 'update'
            ? status(1) : 1;
        change_and_check(
            $storage, $loop, $unloop, timeline => $timeline,
            mode => $mode, target => $target, lable => "mode $mode",
            exp_change => 0, exp_unconfirmed => [], exp_confirmed => []
        );
    }
    note('--- changes done to obtained statuses do not affect storage.');
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test  tl2', count => 'all'
    }, sub {
        my $statuses = shift;
        is(int(@$statuses), 10, "10 statuses");
        $_->{id} = 100 foreach @$statuses;
    };
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test  tl2', count => 'all'
    }, sub {
        my $statuses = shift;
        test_status_id_set($statuses, [1..10], "ID set in storage is not changed.");
    };
    {
        note('--- changes done to inserted/updated statuses do not affect storage.');
        my @upserted = map { status $_ } 1..20;
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test  tl2',
            mode => 'upsert', target => \@upserted, exp_change => 20,
            exp_confirmed => [], exp_unconfirmed => [1..20]
        );
        $_->{id} = 100 foreach @upserted;
        on_statuses $storage, $loop, $unloop, {
            timeline => '_test  tl2', count => 'all'
        }, sub {
            my $statuses = shift;
            test_status_id_set($statuses, [1..20], 'ID set in storage is not changed');
        };
    }

    note('--- clean up');
    foreach my $tl ('_test_tl1', '_test  tl2') {
        $callbacked = 0;
        $storage->delete_statuses(timeline => $tl, callback => sub {
            is(int(@_), 1, "operation succeed");
            $callbacked = 1;
            $unloop->();
        });
        $loop->();
        ok($callbacked, "callbacked");
    }
}

sub test_status_order {
    my ($storage, $loop, $unloop) = @_;
    $loop ||= sub {};
    $unloop ||= sub {};
    note('-------- test_status_order');
    note('--- clear timeline');
    my $callbacked = 0;
    $storage->delete_statuses(timeline => "_test_tl3", callback => sub {
        is(int(@_), 1, "operation succeed");
        $callbacked = 1;
        $unloop->();
    });
    $loop->();
    ok($callbacked, "callbacked");
    note('--- populate timeline');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl3',
        mode => 'insert', target => [map {status $_} (1..30)],
        label => 'first insert',
        exp_change => 30, exp_unconfirmed => [1..30], exp_confirmed => []
    );
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl3',
        mode => 'confirm', target => undef, label => 'confirm all',
        exp_change => 30, exp_unconfirmed => [], exp_confirmed => [1..30]
    );
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl3',
        mode => 'insert', target => [map {status $_} (31..60)],
        label => "another insert", exp_change => 30,
        exp_unconfirmed => [31..60], exp_confirmed => [1..30]
    );
    my %base = (timeline => '_test_tl3');

    note();
    get_and_check_list(
        $storage, $loop, $unloop, {%base, count => 'all'}, [reverse 1..60],
        'get: no max_id, any state, all'
    );
    get_and_check_list(
        $storage, $loop, $unloop, {%base, count => 20}, [reverse 41..60],
        'get: no max_id, any state, partial'
    );
    get_and_check_list(
        $storage, $loop, $unloop, {%base, count => 40}, [reverse 21..60],
        'get: no max_id, any state, both states'
    );
    get_and_check_list(
        $storage, $loop, $unloop, {%base, count => 120}, [reverse 1..60],
        'get: no max_id, any state, count larger than the size'
    );

    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'unconfirmed', count => 'all'},
        [reverse 31..60],
        'get: no max_id unconfirmed, all'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'unconfirmed', count => 15},
        [reverse 46..60 ],
        'get: no max_id, unconfirmed, partial'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'unconfirmed', count => 50},
        [reverse 31..60],
        'get: no max_id, unconfirmed, larger than the unconfirmed size'
    );

    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'confirmed', count => 'all'},
        [reverse 1..30],
        'get: no max_id, confirmed, all'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'confirmed', count => 25},
        [reverse 6..30],
        'get: no max_id, confirmed, partial'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'confirmed', count => 70},
        [reverse 1..30],
        'get: no max_id, confirmed, larger than the confirmed size'
    );
    
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'any', max_id => 40, count => 'all'},
        [reverse 1..40],
        'get: max_id in unconfirmed, any state, all'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'any', max_id => 20, count => 'all'},
        [reverse 1..20],
        'get: max_id in confirmed, any state, all'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'any', max_id => 70, count => 'all'},
        [],
        'get: non-existent max_id, any state, all'
    );

    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'any', max_id => 50, count => 10},
        [reverse 41..50],
        'get: max_id in unconfirmed, any state, count inside unconfirmed zone'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'any', max_id => 50, count => 40},
        [reverse 11..50],
        'get: max_id in unconfirmed, any state, count to confirmed zone'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'any', max_id => 30, count => 20},
        [reverse 11..30],
        'get: max_id in confirmed, any state, partial'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'any', max_id => 10, count => 40},
        [reverse 1..10],
        'get: max_id in confirmed, any state, count larger than the confirmed size'
    );

    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'unconfirmed', max_id => 45, count => 5},
        [reverse 41..45],
        'get: max_id in unconfirmed, unconfirmed state, count in unconfirmed'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'unconfirmed', max_id => 45, count => 25},
        [reverse 31..45],
        'get: max_id in unconfirmed, unconfirmed state, count larger than the unconfirmed size'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'unconfirmed', max_id => 20, count => 5},
        [],
        'get: max_id in confirmed, unconfirmed state'
    );

    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'confirmed', max_id => 50, count => 10},
        [],
        'get: max_id in unconfirmed, confirmed state, count in unconfirmed'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'confirmed', max_id => 45, count => 30},
        [],
        'get: max_id in unconfirmed, confirmed state, count larger than the unconfirmed size'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'confirmed', max_id => 20, count => 10},
        [reverse 11..20],
        'get: max_id in confirmed, confirmed state, count in confirmed'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'confirmed', max_id => 10, count => 30},
        [reverse 1..10],
        'get: max_id in confirmed, confirmed state, count larger than confirmed size'
    );

    {
        note('--- more confirmed statuses');
        my $now = DateTime->now(time_zone => 'UTC');
        my $yesterday = $now - DateTime::Duration->new(days => 1);
        my $tomorrow = $now + DateTime::Duration->new(days => 1);
        my @more_statuses = (
            (map { status $_, 0, $datetime_formatter->format_datetime($tomorrow)  } 61..70),
            (map { status $_, 0, $datetime_formatter->format_datetime($yesterday) }  71..80)
        );
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test_tl3',
            mode => 'insert', target => \@more_statuses,
            exp_change => 20, exp_unconfirmed => [31..60], exp_confirmed => [1..30, 61..80]
        );
    }
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'any', count => 'all'},
        [reverse(71..80, 1..30, 61..70, 31..60)],
        'get: mixed confirmed_at, no max_id, any state, all'
    );
    note('--- move from confirmed to unconfirmed');
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl3', confirmed_state => 'confirmed',
        max_id => 30, count => 10
    }, sub {
        my $statuses = shift;
        delete $_->{busybird}{confirmed_at} foreach @$statuses;
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test_tl3',
            mode => 'update', target => $statuses,
            exp_change => 10,
            exp_unconfirmed => [21..60], exp_confirmed => [1..20, 61..80]
        );
    };
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'any', count => 'all'},
        [reverse(71..80, 1..20, 61..70, 21..60)],
        'get:mixed confirmed_at, no max_id, any state, all'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'any', max_id => 30, count => 30},
        [reverse(11..20, 61..70, 21..30)],
        'get:mixed confirmed_at, max_id in unconfirmed, any state, count larger than unconfirmed size'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'any', max_id => 15, count => 20},
        [reverse(76..80, 1..15)],
        'get:mixed confirmed_at, max_id in confirmed, any state, count in confirmed'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'unconfirmed', max_id => 50, count => 50},
        [reverse(21..50)],
        'get:mixed confirmed_at, max_id in unconfirmed, unconfirmed state, count larger than unconfirmed size'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'confirmed', max_id => 65, count => 30},
        [reverse(76..80, 1..20, 61..65)],
        'get:mixed confirmed_at, max_id in confirmed, confirmed state, count in confirmed area'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'unconfirmed', max_id => 20, count => 30},
        [],
        'get:mixed confirmed_at, max_id in confirmed, unconfirmed state'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'confirmed', max_id => 40, count => 30},
        [],
        'get:mixed confirmed_at, max_id in unconfirmed, confirmed state'
    );

    note('--- messing with created_at');
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl3', count => 'all'
    }, sub {
        my $statuses = shift;
        is(int(@$statuses), 80, "80 statuses");
        foreach my $s (@$statuses) {
            $s->{created_at} = $datetime_formatter->format_datetime(
                $datetime_formatter->parse_datetime($s->{created_at})
                    + DateTime::Duration->new(days => 100 - $s->{id})
            );
        }
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test_tl3',
            mode => 'update', target => $statuses, exp_change => 80,
            exp_unconfirmed => [21..60], exp_confirmed => [1..20, 61..80]
        );
    };
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, confirm_state => 'any', count => 'all'},
        [21..60, 61..70, 1..20, 71..80],
        'sorted by descending order of created_at within confirmed_at group'
    );
}

=pod

=head1 NAME

Test::App::BusyBird::StatusStorage - Test routines for StatusStorage

=head1 FUNCTION

=head2 test_status_storage($storage, $loop, $unloop)

Test the StatusStorage object.
All StatusStorage implementations should pass this test.

C<$storage> is the StatusStorage object to be tested.
C<$loop> is a subroutine reference to go into the event loop,
C<$unloop> is a subroutine reference to go out of the event loop.
If the storage does not use any event loop mechanism, C<$loop> and <$unloop> can be omitted.

In general test of statuses are based on status IDs.
This allows implementations to modify statuses internally.
In addition, statuses are tested unordered.


=head2 test_status_order($storage, $loop, $unloop)

Test the order of statuses obtained by C<get_statuses()> method.

This test assumes the C<$storage> conforms to the "Order of Statuses" guideline
documented in L<App::BusyBird::StatusStorage>.
StatusStorage that does not confirm to the guideline should not run this test.

The arguments are the same as C<test_status_storage> function.


=head1 AUTHOR

Toshio Ito C<< toshioito [at] cpan.org >>

=cut


1;

