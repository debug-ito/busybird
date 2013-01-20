package Test::BusyBird::StatusStorage;
use strict;
use warnings;
use Exporter qw(import);
use DateTime;
use DateTime::Duration;
use Test::More;
use Test::Builder;
use App::BusyBird::DateTime::Format;
use Carp;

our %EXPORT_TAGS = (
    storage => [qw(test_storage_common test_storage_ordered test_storage_truncation)],
    status => [qw(test_status_id_set test_status_id_list)],
);
our @EXPORT_OK = ();
{
    my @all = ();
    foreach my $tag (keys %EXPORT_TAGS) {
        push(@all, @{$EXPORT_TAGS{$tag}});
        push(@EXPORT_OK, @{$EXPORT_TAGS{$tag}});
    }
    $EXPORT_TAGS{all} = \@all;
}

my $datetime_formatter = 'App::BusyBird::DateTime::Format';

sub status {
    my ($id, $level, $acked_at) = @_;
    croak "you must specify id" if not defined $id;
    my $status = {
        id => $id,
        created_at => $datetime_formatter->format_datetime(
            DateTime->from_epoch(epoch => $id)
        ),
    };
    $status->{busybird}{level} = $level if defined $level;
    $status->{busybird}{acked_at} = $acked_at if defined $acked_at;
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

sub acked {
    my ($s) = @_;
    no autovivification;
    return $s->{busybird}{acked_at};
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
    }elsif($args{mode} eq 'delete') {
        my $method = "$args{mode}_statuses";
        my %method_args = (
            timeline => $args{timeline},
            callback => $callback_func,
        );
        $method_args{ids} = $args{target} if exists($args{target});
        $storage->$method(%method_args);
        $loop->();
    }elsif($args{mode} eq 'ack') {
        my $method = "$args{mode}_statuses";
        my %method_args = (
            timeline => $args{timeline},
            callback => $callback_func,
        );
        $method_args{max_id} = $args{target} if exists($args{target});
        $storage->$method(%method_args);
    }else {
        croak "Invalid mode";
    }
    on_statuses $storage, $loop, $unloop, {
        timeline => $args{timeline}, count => 'all',
        ack_state => 'acked'
    }, sub {
        my $statuses = shift;
        test_status_id_set(
            $statuses, $args{exp_acked},
            "$label acked statuses OK"
        );
        foreach my $s (@$statuses) {
            ok(acked($s), "$label acked");
        }
    };
    on_statuses $storage, $loop, $unloop, {
        timeline => $args{timeline}, count => 'all',
        ack_state => 'unacked',
    }, sub {
        my $statuses = shift;
        test_status_id_set(
            $statuses, $args{exp_unacked},
            "$label unacked statuses OK"
        );
        foreach my $s (@$statuses) {
            ok(!acked($s), "$label not acked");
        }
    };
    on_statuses $storage, $loop, $unloop, {
        timeline => $args{timeline}, count => 'all',
        ack_state => 'any',
    }, sub {
        my $statuses = shift;
        test_status_id_set(
            $statuses, [@{$args{exp_acked}}, @{$args{exp_unacked}}],
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


sub test_storage_common {
    my ($storage, $loop, $unloop) = @_;
    note('-------- test_storage_common');
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
            { $storage->get_unacked_counts(timeline => $tl) },
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
        { $storage->get_unacked_counts(timeline => '_test_tl1') },
        { total => 1, 0 => 1 },
        '1 unacked status'
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
        { $storage->get_unacked_counts(timeline => '_test_tl1') },
        { total => 5, 0 => 5 },
        '5 unacked status'
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
                ok(!$s->{busybird}{acked_at}, "status is not acked");
            }
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");

    note('--- ack_statuses: all');
    $callbacked = 0;
    $storage->ack_statuses(
        timeline => '_test_tl1',
        callback => sub {
            my ($num, $error) = @_;
            is(int(@_), 1, "ack_statuses succeed");
            is($num, 5, "5 statuses acked.");
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    is_deeply(
        { $storage->get_unacked_counts(timeline => '_test_tl1') },
        { total => 0 },
        "all acked"
    );
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl1', count => 'all'
    }, sub {
        my $statuses = shift;
        is(int(@$statuses), 5, "5 statueses");
        foreach my $s (@$statuses) {
            no autovivification;
            ok($s->{busybird}{acked_at}, 'acked');
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
        exp_unacked => [1..5], exp_acked => []
    );
    note('--- ack_statuses: with max_id');
    $callbacked = 0;
    $storage->ack_statuses(
        timeline => '_test_tl1', max_id => 3, callback => sub {
            my ($ack_count, $error) = @_;
            is(int(@_), 1, "ack_statuses succeed");
            cmp_ok($ack_count, ">=", 1, "$ack_count (>= 1) acked.");
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, 'callbacked');
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl1', max_id => 3, count => 1
    }, sub {
        my ($statuses, $error) = @_;
        test_status_id_set $statuses, [3], 'get status ID = 3';
        ok(acked($statuses->[0]), 'at least status ID = 3 is acked.');
    };
    note('--- ack_statuses: try to ack already acked statuses');
    $callbacked = 0;
    $storage->ack_statuses(
        timeline => '_test_tl1', max_id => 3, callback => sub {
            my ($ack_count, $error) = @_;
            is(int(@_), 1, 'ack_statuses succeed');
            is($ack_count, 0, 'acks nothing.');
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    note('--- ack_statuses: ack all with max_id => undef');
    $callbacked = 0;
    $storage->ack_statuses(
        timeline => '_test_tl1', max_id => undef, callback => sub {
            my ($ack_count, $error) = @_;
            is(int(@_), 1, 'ack_statuses succeed');
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl1', count => 'all',
    }, sub {
        my $statuses = shift;
        test_status_id_set($statuses, [1..5], "5 statuses");
        foreach my $s (@$statuses) {
            ok(acked($s), "Status ID = $s->{id} is acked");
        }
    };
    note('--- put (insert): try to insert existent status');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'insert', target => status(3), exp_change => 0,
        exp_unacked => [], exp_acked => [1..5]
    );
    note('--- put (update): change to unacked');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'update', target => [map {status($_)} (2,4)], exp_change => 2,
        exp_unacked => [2,4], exp_acked => [1,3,5]
    );
    note('--- ack: try to ack already acked status, again');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'ack', target => 5, exp_change => 0,
        exp_unacked => [2,4], exp_acked => [1,3,5]
    );
    note('--- put (update): change to unacked');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'update', target => [map { status($_) } (3,5)],
        exp_change => 2, exp_unacked => [2,3,4,5], exp_acked => [1]
    );
    is_deeply(
        {$storage->get_unacked_counts(timeline => '_test_tl1')},
        {total => 4, 0 => 4}, '4 unacked statuses'
    );
    note('--- put (update): change level');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'update',
        target => [map { status($_, ($_ % 2 + 1), $_ == 1 ? nowstring() : undef) } (1..5)],
        exp_change => 5, exp_unacked => [2,3,4,5], exp_acked => [1]
    );
    is_deeply(
        {$storage->get_unacked_counts(timeline => '_test_tl1')},
        {total => 4, 1 => 2, 2 => 2}, "4 unacked statuses in 2 levels"
    );
    note('--- put (upsert): acked statuses');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'upsert', target => [map { status($_, 7, nowstring()) } (4..7)],
        exp_change => 4, exp_unacked => [2,3], exp_acked => [1,4..7]
    );
    note('--- get and put(update): back to unacked');
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl1', count => 'all', ack_state => 'acked'
    }, sub {
        my $statuses = shift;
        delete $_->{busybird}{acked_at} foreach @$statuses;
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test_tl1',
            mode => 'update', target => $statuses,
            exp_change => 5, exp_unacked => [1..7], exp_acked => []
        );
    };
    is_deeply(
        {$storage->get_unacked_counts(timeline => '_test_tl1')},
        {total => 7, 1 => 1, 2 => 2, 7 => 4}, "3 levels"
    );

    note('--- put(insert): to another timeline');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test  tl2',
        mode => 'insert', target => [map { status($_) } (1..10)],
        exp_change => 10, exp_unacked => [1..10], exp_acked => []
    );
    is_deeply(
        {$storage->get_unacked_counts(timeline => '_test  tl2')},
        {total => 10, 0 => 10}, '10 unacked statuses'
    );
    ## change_and_check(
    ##     $storage, $loop, $unloop, timeline => '_test  tl2',
    ##     mode => 'ack', target => [1..5],
    ##     exp_change => 5, exp_unacked => [6..10], exp_acked => [1..5]
    ## );
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test  tl2',
        mode => 'update', target => [map {status($_, undef, nowstring())} (1..5)],
        exp_change => 5, exp_unacked => [6..10], exp_acked => [1..5]
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
        my $correct_state = ($id <= 5) ? 'acked' : 'unacked';
        my $wrong_state = $correct_state eq 'acked' ? 'unacked' : 'acked';
        on_statuses $storage, $loop, $unloop, {
            timeline => '_test  tl2', count => 1, max_id => $id,
            ack_state => $correct_state,
        }, sub {
            my $statuses = shift;
            is(int(@$statuses), 1, "get 1 status");
            is($statuses->[0]{id}, $id, "... and its ID is $id");
        };
        foreach my $count ('all', 1, 10) {
            on_statuses $storage, $loop, $unloop, {
                timeline => '_test  tl2', count => $count, max_id => $id,
                ack_state => $wrong_state
            }, sub {
                my $statuses = shift;
                is(int(@$statuses), 0,
                   "no status returned when status specified" . 
                       " max_id is not the correct ack_state".
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
    foreach my $test_set (
        {mode => 'update', target => [map { status($_) } (11..15) ]},
        {mode => 'delete', target => [11..15]},
        {mode => 'ack', target => 11}
    ) {
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test  tl2',
            mode => $test_set->{mode}, target => $test_set->{target}, label => "mode $test_set->{mode}",
            exp_change => 0, exp_unacked => [6..10],
            exp_acked => [1..5]
        );
    }
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test  tl2', count => 'all', max_id => 15,
    }, sub {
        my $statuses = shift;
        is(int(@$statuses), 0, "get max_id=15 returns empty");
    };
    note('--- access to non-existent timeline');
    foreach my $mode (qw(update delete ack)) {
        my $timeline = '_this_timeline_ probably does not exist';
        my $target = $mode eq 'update'
            ? status(1) : 1;
        change_and_check(
            $storage, $loop, $unloop, timeline => $timeline,
            mode => $mode, target => $target, lable => "mode $mode",
            exp_change => 0, exp_unacked => [], exp_acked => []
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
            exp_acked => [], exp_unacked => [1..20]
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

sub test_storage_ordered {
    my ($storage, $loop, $unloop) = @_;
    $loop ||= sub {};
    $unloop ||= sub {};
    note('-------- test_storage_ordered');
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
        exp_change => 30, exp_unacked => [1..30], exp_acked => []
    );
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl3',
        mode => 'ack', target => undef, label => 'ack all',
        exp_change => 30, exp_unacked => [], exp_acked => [1..30]
    );
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl3',
        mode => 'insert', target => [map {status $_} (31..60)],
        label => "another insert", exp_change => 30,
        exp_unacked => [31..60], exp_acked => [1..30]
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
        {%base, ack_state => 'unacked', count => 'all'},
        [reverse 31..60],
        'get: no max_id unacked, all'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'unacked', count => 15},
        [reverse 46..60 ],
        'get: no max_id, unacked, partial'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'unacked', count => 50},
        [reverse 31..60],
        'get: no max_id, unacked, larger than the unacked size'
    );

    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'acked', count => 'all'},
        [reverse 1..30],
        'get: no max_id, acked, all'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'acked', count => 25},
        [reverse 6..30],
        'get: no max_id, acked, partial'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'acked', count => 70},
        [reverse 1..30],
        'get: no max_id, acked, larger than the acked size'
    );
    
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'any', max_id => 40, count => 'all'},
        [reverse 1..40],
        'get: max_id in unacked, any state, all'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'any', max_id => 20, count => 'all'},
        [reverse 1..20],
        'get: max_id in acked, any state, all'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'any', max_id => 70, count => 'all'},
        [],
        'get: non-existent max_id, any state, all'
    );

    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'any', max_id => 50, count => 10},
        [reverse 41..50],
        'get: max_id in unacked, any state, count inside unacked zone'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'any', max_id => 50, count => 40},
        [reverse 11..50],
        'get: max_id in unacked, any state, count to acked zone'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'any', max_id => 30, count => 20},
        [reverse 11..30],
        'get: max_id in acked, any state, partial'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'any', max_id => 10, count => 40},
        [reverse 1..10],
        'get: max_id in acked, any state, count larger than the acked size'
    );

    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'unacked', max_id => 45, count => 5},
        [reverse 41..45],
        'get: max_id in unacked, unacked state, count in unacked'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'unacked', max_id => 45, count => 25},
        [reverse 31..45],
        'get: max_id in unacked, unacked state, count larger than the unacked size'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'unacked', max_id => 20, count => 5},
        [],
        'get: max_id in acked, unacked state'
    );

    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'acked', max_id => 50, count => 10},
        [],
        'get: max_id in unacked, acked state, count in unacked'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'acked', max_id => 45, count => 30},
        [],
        'get: max_id in unacked, acked state, count larger than the unacked size'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'acked', max_id => 20, count => 10},
        [reverse 11..20],
        'get: max_id in acked, acked state, count in acked'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'acked', max_id => 10, count => 30},
        [reverse 1..10],
        'get: max_id in acked, acked state, count larger than acked size'
    );

    {
        note('--- more acked statuses');
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
            exp_change => 20, exp_unacked => [31..60], exp_acked => [1..30, 61..80]
        );
    }
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'any', count => 'all'},
        [reverse(71..80, 1..30, 61..70, 31..60)],
        'get: mixed acked_at, no max_id, any state, all'
    );
    note('--- move from acked to unacked');
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl3', acked_state => 'acked',
        max_id => 30, count => 10
    }, sub {
        my $statuses = shift;
        delete $_->{busybird}{acked_at} foreach @$statuses;
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test_tl3',
            mode => 'update', target => $statuses,
            exp_change => 10,
            exp_unacked => [21..60], exp_acked => [1..20, 61..80]
        );
    };
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'any', count => 'all'},
        [reverse(71..80, 1..20, 61..70, 21..60)],
        'get:mixed acked_at, no max_id, any state, all'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'any', max_id => 30, count => 30},
        [reverse(11..20, 61..70, 21..30)],
        'get:mixed acked_at, max_id in unacked, any state, count larger than unacked size'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'any', max_id => 15, count => 20},
        [reverse(76..80, 1..15)],
        'get:mixed acked_at, max_id in acked, any state, count in acked'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'unacked', max_id => 50, count => 50},
        [reverse(21..50)],
        'get:mixed acked_at, max_id in unacked, unacked state, count larger than unacked size'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'acked', max_id => 65, count => 30},
        [reverse(76..80, 1..20, 61..65)],
        'get:mixed acked_at, max_id in acked, acked state, count in acked area'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'unacked', max_id => 20, count => 30},
        [],
        'get:mixed acked_at, max_id in acked, unacked state'
    );
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'acked', max_id => 40, count => 30},
        [],
        'get:mixed acked_at, max_id in unacked, acked state'
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
            exp_unacked => [21..60], exp_acked => [1..20, 61..80]
        );
    };
    get_and_check_list(
        $storage, $loop, $unloop,
        {%base, ack_state => 'any', count => 'all'},
        [21..60, 61..70, 1..20, 71..80],
        'sorted by descending order of created_at within acked_at group'
    );
    
    fail('ack_statuses: ordered test. which statuses are acked by ack_statuses with max_id ??');
}

sub test_storage_truncation {
    my ($storage, $max_status_num, $loop, $unloop) = @_;
    note("-------- test_storage_truncation max_status_num = $max_status_num");
    $loop ||= sub {};
    $unloop ||= sub {};
    $max_status_num = int($max_status_num);
    croak 'max_status_num must be bigger than 0' if $max_status_num <= 0;
    note('--- clear the timeline');
    my $callbacked = 0;
    my %base = (timeline => '_test_tl4');
    $storage->delete_statuses(%base, callback => sub {
        $callbacked = 1;
        $unloop->();
    });
    $loop->();
    ok($callbacked, 'callbacked');
    on_statuses $storage, $loop, $unloop, {
        %base, count => 'all'
    }, sub {
        my ($statuses) = @_;
        is(int(@$statuses), 0, 'no statuses');
    };
    note('--- populate to the max');
    change_and_check(
        $storage, $loop, $unloop, %base,
        mode => 'insert', target => [map {status($_)} (1..$max_status_num)],
        exp_change => $max_status_num, exp_unacked => [1..$max_status_num],
        exp_acked => []
    );
    note('--- insert another one');
    change_and_check(
        $storage, $loop, $unloop, %base,
        mode => 'insert', target => status($max_status_num+1),
        exp_change => 1, exp_unacked => [2..($max_status_num+1)],
        exp_acked => []
    );
    note('--- insert multiple statuses');
    change_and_check(
        $storage, $loop, $unloop, %base,
        mode => 'insert', target => [map { status($max_status_num+1+$_) } 1..4],
        exp_change => 4, exp_unacked => [6..($max_status_num+5)],
        exp_acked => []
    );
    note('--- the top to acked');
    on_statuses $storage, $loop, $unloop, {
        %base, count => 1, max_id => ($max_status_num+5)
    }, sub {
        my ($statuses) = @_;
        $statuses->[0]{busybird}{acked_at} = nowstring();
        change_and_check(
            $storage, $loop, $unloop, %base,
            mode => 'update', target => $statuses,
            exp_change => 1, exp_unacked => [6 .. $max_status_num+4],
            exp_acked => [$max_status_num+5]
        );
    };
    note('--- inserting another one removes the acked status');
    change_and_check(
        $storage, $loop, $unloop, %base,
        mode => 'insert', target => status($max_status_num+6),
        exp_change => 1, exp_unacked => [6 .. $max_status_num+4, $max_status_num+6],
        exp_acked => []
    );
}

=pod

=head1 NAME

Test::BusyBird::StatusStorage - Test routines for StatusStorage

=head1 SYNOPSIS


    use My::Storage;
    use Test::More;
    use Test::BusyBird::StatusStorage qw(:storage);
    
    my $storage = My::Storage->new();
    test_storage_common($storage);
    test_storage_ordered($storage);
    done_testing();


=head1 DESCRIPTION

This module provides some functions mainly for testing StatusStorage objects.

This module exports nothing by default, but the following functions can be imported explicitly.
The functions are categorized by tags.

If you want to import all functions, import C<:all> tag.


=head1 :storage TAG FUNCTIONS

=head2 test_storage_common($storage, $loop, $unloop)

Test the StatusStorage object.
All StatusStorage implementations should pass this test.

C<$storage> is the StatusStorage object to be tested.
C<$loop> is a subroutine reference to go into the event loop,
C<$unloop> is a subroutine reference to go out of the event loop.
If the storage does not use any event loop mechanism, C<$loop> and <$unloop> can be omitted.

In general test of statuses are based on status IDs.
This allows implementations to modify statuses internally.
In addition, statuses are tested unordered.


=head2 test_storage_ordered($storage, $loop, $unloop)

Test the order of statuses obtained by C<get_statuses()> method.

This test assumes the C<$storage> conforms to the "Order of Statuses" guideline
documented in L<App::BusyBird::StatusStorage>.
StatusStorage that does not conform to the guideline should not run this test.

The arguments are the same as C<test_storage_common> function.


=head2 test_storage_truncation($storage, $max_status_num $loop, $unloop)

Test if statuses are properly truncated in the storage.

This test assumes the C<$storage> passes C<test_storage_ordered()> test.
In each timeline, the "oldest" status should be removed first.

C<$storage> is the StatusStorage object to be tested.
C<$max_status_num> is the maximum number of statuses per timeline
that C<$storage> can store.
C<$loop> and C<$unloop> are the same as C<test_storage_common> function.



=head1 :status TAG FUNCTIONS

=head2 test_status_id_set ($got_statuses, $exp_statuses_or_ids, $msg)

Test if the set of statuses is expected.

This function only checks IDs of given statuses. The test does not care about any other fields
in statuses. This function does not care about the order of statuses either.

C<$got_statuses> is an array-ref of status objects to be tested.
C<$exp_statues_or_ids> is an array-ref of status objects or IDs that are expected.
C<$msg> is the test message.

=head2 test_status_id_list ($got_statuses, $exp_statuses_or_ids, $msg)

Almost the same as the C<test_status_id_set> function, but this test DOES care the order of statuses.


=head1 AUTHOR

Toshio Ito C<< toshioito [at] cpan.org >>

=cut


1;

