package BusyBird::Test::StatusStorage;
use strict;
use warnings;
use Exporter qw(import);
use DateTime;
use DateTime::Duration;
use Test::More;
use Test::Builder;
use Test::Exception;
use BusyBird::DateTime::Format;
use BusyBird::StatusStorage;
use Carp;

our %EXPORT_TAGS = (
    storage => [
        qw(test_storage_common test_storage_ordered test_storage_truncation test_storage_missing_arguments),
        qw(test_storage_put_requires_ids),
    ],
    status => [qw(test_status_id_set test_status_id_list)],
);
our @EXPORT_OK = qw(test_cases_for_ack);
{
    my @all = ();
    foreach my $tag (keys %EXPORT_TAGS) {
        push(@all, @{$EXPORT_TAGS{$tag}});
        push(@EXPORT_OK, @{$EXPORT_TAGS{$tag}});
    }
    $EXPORT_TAGS{all} = \@all;
}

my $datetime_formatter = 'BusyBird::DateTime::Format';

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

sub add_datetime_days {
    my ($datetime_str, $days) = @_;
    my $dtd = DateTime::Duration->new(days => ($days > 0 ? $days : -$days));
    my $orig_dt = $datetime_formatter->parse_datetime($datetime_str);
    return $datetime_formatter->format_datetime(
        ($days > 0) ? ($orig_dt + $dtd) : ($orig_dt - $dtd)
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
        my $error = shift;
        $statuses = shift;
        is($error, undef, 'operation succeed');
        $callbacked = 1;
        $unloop->();
    });
    $loop->();
    ok($callbacked, 'callbacked');
    return $statuses;
}

sub sync_get_unacked_counts {
    my ($storage, $loop, $unloop, $timeline) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $callbacked = 0;
    my $result;
    $storage->get_unacked_counts(
        timeline => $timeline, callback => sub {
            my ($error, $unacked_counts) = @_;
            is($error, undef, 'operation succeed');
            $result = $unacked_counts;
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, 'callbacked');
    return %$result;
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
        my ($error, $result) = @_;
        is($error, undef, "$label $args{mode} succeed.");
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
        $method_args{max_id} = $args{target_max_id} if exists($args{target_max_id});
        $method_args{ids} = $args{target_ids} if exists($args{target_ids});
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

sub test_cases_for_ack {
    ## ** assumption: acked [1..10] (sufficiently old), unacked [11..20]
    my (%args) = @_;
    if($args{is_ordered}) {
        return (
            {label => 'max_id', req => {max_id => 14}, exp_count => 4,
             exp_unacked => [reverse 15..20], exp_acked => [reverse 1..14]},
            {label => 'max_id with ids < max_id', req => {ids => 12, max_id => 15}, exp_count => 5,
             exp_unacked => [reverse 16..20], exp_acked => [reverse 1..15]},
            {label => 'max_id with ids > max_id', req => {ids => [15,17], max_id => 13}, exp_count => 5,
             exp_unacked => [reverse 14,16,18..20], exp_acked => [reverse 1..13,15,17]},
            {label => 'max_id with ids = max_id', req => {ids => 15, max_id => 15}, exp_count => 5,
             exp_unacked => [reverse 16..20], exp_acked => [reverse 1..15]},
            {label => 'max_id with ids all cases', req => {ids => [4,14,18,20,24], max_id => 18}, exp_count => 9,
             exp_unacked => [19], exp_acked => [reverse 1..18,20]}
        );
    }else {
        return (
            {label => "no body", req => undef, exp_count => 10,
             exp_unacked => [], exp_acked => [reverse 1..20]},
            {label => "empty", req => {}, exp_count => 10,
             exp_unacked => [], exp_acked => [reverse 1..20]},
            {label => 'both null', req => {ids => undef, max_id => undef}, exp_count => 10,
             exp_unacked => [], exp_acked => [reverse 1..20]},
            {label => 'empty ids', req => {ids => []}, exp_count => 0,
             exp_unacked => [reverse 11..20], exp_acked => [reverse 1..10]},
            {label => 'empty ids with undef max_id', req => {ids => [], max_id => undef}, exp_count => 0,
             exp_unacked => [reverse 11..20], exp_acked => [reverse 1..10]},
            {label => 'single ids', req => {ids => 15}, exp_count => 1,
             exp_unacked => [reverse 11..14,16..20], exp_acked => [reverse 1..10,15]},
            {label => 'multi ids', req => {ids => [13,14,15]}, exp_count => 3,
             exp_unacked => [reverse 11,12,16..20], exp_acked => [reverse 1..10,13,14,15]},
            {label => 'multi ids with unknown id', req => {ids => [19..23]}, exp_count => 2,
             exp_unacked => [reverse 11..18], exp_acked => [reverse 1..10,19,20]},
            {label => 'multi ids with acked id', req => {ids => [8..14]}, exp_count => 4,
             exp_unacked => [reverse 15..20], exp_acked => [reverse 1..14]},
            {label => 'multi ids (all unknown)', req => {ids => [-1,-4,21,24]}, exp_count => 0,
             exp_unacked => [reverse 11..20], exp_acked => [reverse 1..10]},
            {label => 'max_id to unknown id', req => {max_id => 23}, exp_count => 0,
             exp_unacked => [reverse 11..20], exp_acked => [reverse 1..10]},
            {label => 'max_id to acked id', req => {max_id => 7}, exp_count => 0,
             exp_unacked => [reverse 11..20], exp_acked => [reverse 1..10]},
        );
    }
}


sub test_storage_common {
    my ($storage, $loop, $unloop) = @_;
    note('-------- test_storage_common');
    $loop ||= sub {};
    $unloop ||= sub {};
    my $callbacked = 0;
    isa_ok($storage, 'BusyBird::StatusStorage');
    can_ok($storage, 'get_unacked_counts', map { "${_}_statuses" } qw(ack get put delete));
    note("--- clear the timelines");
    foreach my $tl ('_test_tl1', "_test_tl2") {
        $callbacked = 0;
        $storage->delete_statuses(
            timeline => $tl,
            ids => undef,
            callback => sub {
                $callbacked = 1;
                $unloop->();
            }
        );
        $loop->();
        ok($callbacked, "callbacked");
        is_deeply(
            { sync_get_unacked_counts($storage, $loop, $unloop, $tl) },
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
            my ($error, $num) = @_;
            is($error, undef, 'put_statuses succeed.');
            is($num, 1, 'put 1 status');
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    is_deeply(
        { sync_get_unacked_counts($storage, $loop, $unloop, '_test_tl1') },
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
            my ($error, $num) = @_;
            is($error, undef, 'put_statuses succeed');
            is($num, 4, 'put 4 statuses');
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    is_deeply(
        { sync_get_unacked_counts($storage, $loop, $unloop, '_test_tl1') },
        { total => 5, 0 => 5 },
        '5 unacked status'
    );

    note('--- get_statuses: any, all');
    $callbacked = 0;
    $storage->get_statuses(
        timeline => '_test_tl1',
        count => 'all',
        callback => sub {
            my ($error, $statuses) = @_;
            is($error, undef, "get_statuses succeed");
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
            my ($error, $num) = @_;
            is($error, undef, "ack_statuses succeed");
            is($num, 5, "5 statuses acked.");
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    is_deeply(
        { sync_get_unacked_counts($storage, $loop, $unloop, '_test_tl1') },
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
            my ($error, $num) = @_;
            is($error, undef, "operation succeed.");
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
            my ($error, $num) = @_;
            is($error, undef, 'operation succeed');
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
            my ($error, $num) = @_;
            is($error, undef, 'operation succeed');
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
            my ($error, $ack_count) = @_;
            is($error, undef, "ack_statuses succeed");
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
        my ($statuses) = @_;
        test_status_id_set $statuses, [3], 'get status ID = 3';
        ok(acked($statuses->[0]), 'at least status ID = 3 is acked.');
    };
    note('--- ack_statuses: ack all with max_id => undef');
    $callbacked = 0;
    $storage->ack_statuses(
        timeline => '_test_tl1', max_id => undef, callback => sub {
            my ($error, $ack_count) = @_;
            is($error, undef, 'ack_statuses succeed');
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
    note('--- put (update): change to unacked');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl1',
        mode => 'update', target => [map { status($_) } (3,5)],
        exp_change => 2, exp_unacked => [2,3,4,5], exp_acked => [1]
    );
    is_deeply(
        {sync_get_unacked_counts($storage, $loop, $unloop, '_test_tl1')},
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
        {sync_get_unacked_counts($storage, $loop, $unloop, '_test_tl1')},
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
        {sync_get_unacked_counts($storage, $loop, $unloop, '_test_tl1')},
        {total => 7, 1 => 1, 2 => 2, 7 => 4}, "3 levels"
    );

    note('--- put(insert): to another timeline');
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl2',
        mode => 'insert', target => [map { status($_) } (1..10)],
        exp_change => 10, exp_unacked => [1..10], exp_acked => []
    );
    is_deeply(
        {sync_get_unacked_counts($storage, $loop, $unloop, '_test_tl2')},
        {total => 10, 0 => 10}, '10 unacked statuses'
    );
    ## change_and_check(
    ##     $storage, $loop, $unloop, timeline => '_test_tl2',
    ##     mode => 'ack', target => [1..5],
    ##     exp_change => 5, exp_unacked => [6..10], exp_acked => [1..5]
    ## );
    change_and_check(
        $storage, $loop, $unloop, timeline => '_test_tl2',
        mode => 'update', target => [map {status($_, undef, nowstring())} (1..5)],
        exp_change => 5, exp_unacked => [6..10], exp_acked => [1..5]
    );
    note('--- get: single, any state');
    foreach my $id (1..10) {
        on_statuses $storage, $loop, $unloop, {
            timeline => '_test_tl2', count => 1, max_id => $id
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
            timeline => '_test_tl2', count => 1, max_id => $id,
            ack_state => $correct_state,
        }, sub {
            my $statuses = shift;
            is(int(@$statuses), 1, "get 1 status");
            is($statuses->[0]{id}, $id, "... and its ID is $id");
        };
        foreach my $count ('all', 1, 10) {
            on_statuses $storage, $loop, $unloop, {
                timeline => '_test_tl2', count => $count, max_id => $id,
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
        timeline => '_test_tl2', count => "all",
    }, sub {
        my $statuses = shift;
        test_status_id_set($statuses, [1..10], "10 statuses in _test_tl2");
    };
    note('--- access to non-existent statuses');
    foreach my $test_set (
        {mode => 'update', target => [map { status($_) } (11..15) ]},
        {mode => 'delete', target => [11..15]},
    ) {
        my $label = "mode $test_set->{mode} " . ($test_set->{label} || "");
        my %target_args = %$test_set;
        delete @target_args{"mode", "label"};
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test_tl2',
            mode => $test_set->{mode}, label => $label, %target_args,
            exp_change => 0, exp_unacked => [6..10],
            exp_acked => [1..5]
        );
    }
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl2', count => 'all', max_id => 15,
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
        timeline => '_test_tl2', count => 'all'
    }, sub {
        my $statuses = shift;
        is(int(@$statuses), 10, "10 statuses");
        $_->{id} = 100 foreach @$statuses;
    };
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl2', count => 'all'
    }, sub {
        my $statuses = shift;
        test_status_id_set($statuses, [1..10], "ID set in storage is not changed.");
    };
    {
        note('--- changes done to inserted/updated statuses do not affect storage.');
        my @upserted = map { status $_ } 1..20;
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test_tl2',
            mode => 'upsert', target => \@upserted, exp_change => 20,
            exp_acked => [], exp_unacked => [1..20]
        );
        $_->{id} = 100 foreach @upserted;
        on_statuses $storage, $loop, $unloop, {
            timeline => '_test_tl2', count => 'all'
        }, sub {
            my $statuses = shift;
            test_status_id_set($statuses, [1..20], 'ID set in storage is not changed');
        };
    }

    {
        note('--- -- test acks with max_id (unordered)');
        $callbacked = 0;
        $storage->delete_statuses(timeline => '_test_acks', ids => undef, callback => sub {
            $callbacked = 1;
            $unloop->();
        });
        $loop->();
        ok($callbacked, 'callbacked');
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test_acks',
            mode => 'insert', target => [map {status($_)} 1..30], exp_change => 30,
            exp_acked => [], exp_unacked => [1..30]
        );
        note('--- ack: ids and max_id (max_id < ids)');
        $callbacked = 0;
        $storage->ack_statuses(timeline => '_test_acks', ids => [25..28], max_id => 4, callback => sub {
            my ($error, $count) = @_;
            $callbacked = 1;
            is($error, undef, "ack_statuses succeed");
            cmp_ok($count, ">=", 5, 'at least 5 statuses acked.');
            $unloop->();
        });
        $loop->();
        ok($callbacked, "callbacked");
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test_acks',
            mode => 'delete', target => undef, exp_change => 30, exp_acked => [], exp_unacked => []
        );
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test_acks',
            mode => 'insert', target => [map {status($_)} 31..40], exp_change => 10, exp_acked => [], exp_unacked => [31..40]
        );
        note('--- ack: ids and max_id (max_id > ids)');
        $callbacked = 0;
        $storage->ack_statuses(timeline => '_test_acks', ids => 32, max_id => 39, callback => sub {
            my ($error, $count) = @_;
            $callbacked = 1;
            is($error, undef, 'ack_statuses succeed');
            cmp_ok($count, ">=", 2, "at least 2 statuses acked");
            $unloop->();
        });
        $loop->();
        ok($callbacked, "callbacked");
        change_and_check(
            $storage, $loop, $unloop, timeline => '_test_acks',
            mode => 'delete', target => undef, exp_change => 10, exp_acked => [], exp_unacked => []
        );
    }

    {
        note('--- -- acks with various argument cases (unordered)');
        foreach my $case (test_cases_for_ack(is_ordered => 0)) {
            my $callbacked = 0;
            next if not defined $case->{req};
            note("--- case: $case->{label}");
            $storage->delete_statuses(timeline => '_test_acks', ids => undef, callback => sub {
                my ($error, $count) = @_;
                is($error, undef, "delete succeed");
                $callbacked = 1;
                $unloop->();
            });
            $loop->();
            ok($callbacked, 'callbacked');
            my $already_acked_at = nowstring();
            change_and_check(
                $storage, $loop, $unloop, timeline => '_test_acks', mode => 'insert',
                target => [(map {status($_, 0, $already_acked_at)} 1..10), (map {status($_)} 11..20)],
                exp_change => 20, exp_acked => [1..10], exp_unacked => [11..20]
            );
            my %target_args = ();
            $target_args{target_ids} = $case->{req}{ids} if exists $case->{req}{ids};
            $target_args{target_max_id} = $case->{req}{max_id} if exists $case->{req}{max_id};
            change_and_check(
                $storage, $loop, $unloop, timeline => '_test_acks', mode => 'ack',
                %target_args, exp_change => $case->{exp_count}, exp_acked => $case->{exp_acked}, exp_unacked => $case->{exp_unacked}
            );
        }
    }

    note('--- clean up');
    foreach my $tl ('_test_tl1', '_test_tl2') {
        $callbacked = 0;
        $storage->delete_statuses(timeline => $tl, ids => undef, callback => sub {
            my $error= shift;
            is($error, undef, "operation succeed");
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
    foreach my $tl (qw(_test_tl3 _test_tl4 _test_tl5)) {
        $callbacked = 0;
        $storage->delete_statuses(timeline => $tl, ids => undef, callback => sub {
            my $error = shift;
            is($error, undef, "operation succeed");
            $callbacked = 1;
            $unloop->();
        });
        $loop->();
        ok($callbacked, "callbacked");    
    }
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

    note('--- -- ack test');
    note('--- change acked_at for testing');
    on_statuses $storage, $loop, $unloop, {
        %base, count => 'all', ack_state => 'acked'
    }, sub {
        my $statuses = shift;
        foreach my $s (@$statuses) {
            $s->{busybird}{acked_at} =
                add_datetime_days($s->{busybird}{acked_at}, +2);
        }
        change_and_check(
            $storage, $loop, $unloop, %base, mode => 'update',
            target => $statuses, exp_change => 40,
            exp_unacked => [21..60], exp_acked => [61..70, 1..20, 71..80]
        );
    };
    change_and_check(
        $storage, $loop, $unloop, %base, mode => 'ack', target => 51,
        exp_change => 10, exp_unacked => [21..50], exp_acked => [61..70, 1..20, 71..80, 51..60]
    );
    get_and_check_list(
        $storage, $loop, $unloop, {%base, ack_state => 'any', count => 'all'},
        [21..50, 61..70, 1..20, 71..80, 51..60],
        '10 acked statuses are at the bottom, because other acked statuses have acked_at of future.'
    );
    
    note('--- populate another timeline');
    my %base4 = (timeline => '_test_tl4');
    $callbacked = 0;
    $storage->delete_statuses(%base4, ids => undef, callback => sub {
        my $error = shift;
        is($error, undef, "delete succeed");
        $callbacked = 1;
        $unloop->();
    });
    $loop->();
    ok($callbacked, "callbacked");
    change_and_check(
        $storage, $loop, $unloop, %base4,
        mode => 'insert', target => [map {status($_)} (31..40)],
        exp_change => 10, exp_unacked => [31..40], exp_acked => []
    );
    get_and_check_list(
        $storage, $loop, $unloop, {%base4, count => 'all'}, [reverse 31..40],
        '10 unacked'
    );
    change_and_check(
        $storage, $loop, $unloop, %base4,
        mode => 'ack', target => 35, exp_change => 5,
        exp_unacked => [36..40], exp_acked => [31..35]
    );
    get_and_check_list(
        $storage, $loop, $unloop, {%base4, count => 'all', ack_state => 'acked'},
        [reverse 31..35], '5 acked'
    );
    change_and_check(
        $storage, $loop, $unloop, %base4,
        mode => 'insert', target => [map {status($_)} (26..30, 41..45)],
        exp_change => 10, exp_unacked => [26..30, 36..45], exp_acked => [31..35]
    );
    get_and_check_list(
        $storage, $loop, $unloop, {%base4, count => 'all', ack_state => 'unacked'},
        [reverse 26..30, 36..45], '15 unacked statuses'
    );
    note('--- For testing, set acked_at sufficiently old.');
    on_statuses $storage, $loop, $unloop, {
        %base4, count => 'all', ack_state => 'acked'
    }, sub {
        my $statuses = shift;
        foreach my $s (@$statuses) {
            $s->{busybird}{acked_at} = add_datetime_days($s->{busybird}{acked_at}, -1);
        }
        change_and_check(
            $storage, $loop, $unloop, %base4, mode => 'update', target => $statuses,
            exp_change => 5, exp_unacked => [26..30, 36..45], exp_acked => [31..35]
        );
    };
    change_and_check(
        $storage, $loop, $unloop, %base4, mode => 'ack', target => 40, exp_change => 10,
        exp_unacked => [41..45], exp_acked => [36..40, 26..30, 31..35]
    );
    get_and_check_list(
        $storage, $loop, $unloop, {%base4, count => 'all', ack_state => 'acked'},
        [reverse(36..40), reverse(26..30), reverse(31..35)]
    );
    change_and_check(
        $storage, $loop, $unloop, %base4, mode => 'ack', exp_change => 5,
        exp_unacked => [], exp_acked => [26..45]
    );
    {
        note('--- same timestamp: order is free, but must be consistent.');
        my %base5 = (timeline => '_test_tl5');
        my @in_statuses = map {status($_)} (1..10);
        my $created_at = nowstring;
        $_->{created_at} = $created_at foreach @in_statuses;
        change_and_check(
            $storage, $loop, $unloop, %base5, mode => 'insert', target => [@in_statuses[0..4]],
            label => 'insert first five', exp_change => 5, exp_unacked => [1..5], exp_acked => []
        );
        change_and_check(
            $storage, $loop, $unloop, %base5, mode => 'ack', target => undef,
            label => 'ack first five', exp_change => 5, exp_unacked => [], exp_acked => [1..5]
        );
        change_and_check(
            $storage, $loop, $unloop, %base5, mode => 'insert', target => [@in_statuses[5..9]],
            label => 'insert next five', exp_change => 5, exp_unacked => [6..10], exp_acked => [1..5]
        );
        my $whole_timeline = sync_get($storage, $loop, $unloop, %base5, count => 'all');
        foreach my $start_index (0..9) {
            my $max_id = $whole_timeline->[$start_index]{id};
            get_and_check_list(
                $storage, $loop, $unloop, {%base5, count => 'all', max_id => $max_id},
                [ map {$_->{id}} @{$whole_timeline}[$start_index .. 9] ],
                "start_index = $start_index, max_id = $max_id: order is the same as the whole_timeline"
            );
        }
    }

    {
        note('--- -- acks with various argument cases (ordered)');
        foreach my $case (test_cases_for_ack(is_ordered => 1)) {
            my $callbacked = 0;
            next if not defined $case->{req};
            note("--- case: $case->{label}");
            $storage->delete_statuses(timeline => '_test_acks', ids => undef, callback => sub {
                my ($error, $count) = @_;
                is($error, undef, "delete succeed");
                $callbacked = 1;
                $unloop->();
            });
            $loop->();
            ok($callbacked, 'callbacked');
            my $already_acked_at = add_datetime_days(nowstring(), -1);
            change_and_check(
                $storage, $loop, $unloop, timeline => '_test_acks', mode => 'insert',
                target => [(map {status($_, 0, $already_acked_at)} 1..10), (map {status($_)} 11..20)],
                exp_change => 20, exp_acked => [1..10], exp_unacked => [11..20]
            );
            my %target_args = ();
            $storage->ack_statuses(timeline => '_test_acks', %{$case->{req}}, callback => sub {
                my ($error, $count) = @_;
                is($error, undef, "ack succeed");
                is($count, $case->{exp_count}, "count is $case->{exp_count}");
                $callbacked = 1;
                $unloop->();
            });
            $loop->();
            ok($callbacked, "callbacked");
            get_and_check_list(
                $storage, $loop, $unloop, {timeline => '_test_acks', count => 'all', ack_state => 'acked'},
                $case->{exp_acked}, "ordered acked statuses OK"
            );
            get_and_check_list(
                $storage, $loop, $unloop, {timeline => '_test_acks', count => 'all', ack_state => 'unacked'},
                $case->{exp_unacked}, "ordered unacked statuses OK"
            );
        }
    }
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
    $storage->delete_statuses(%base, ids => undef, callback => sub {
        my $error = shift;
        is($error, undef, "delete succeed");
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

sub test_storage_missing_arguments {
    my ($storage, $loop, $unloop) = @_;
    note("-------- test_storage_missing_arguments");
    dies_ok { $storage->ack_statuses() } 'ack: timeline is missing';
    dies_ok { $storage->get_statuses(callback => sub {}) } 'get: timeline is missing';
    dies_ok { $storage->get_statuses(timeline => 'tl') } 'get: callback is missing';
    dies_ok {
        $storage->put_statuses(mode => 'insert', statuses => []);
    } 'put: timeline is missing';
    dies_ok {
        $storage->put_statuses(timeline => 'tl', mode => 'insert');
    } 'put: statuses is missing';
    dies_ok {
        $storage->put_statuses(timeline => 'tl', statuses => []);
    } 'put: mode is missing';
    dies_ok { $storage->delete_statuses(ids => undef) } 'delete: timeline is missing';
    dies_ok { $storage->delete_statuses(timeline => 'tl') } 'delete: ids is missing';
    dies_ok { $storage->get_unacked_counts(callback => sub {}) } 'get_unacked: timeline is missing';
    dies_ok { $storage->get_unacked_counts(timeline => 'tl') } 'get_unacked: callback is missing';
}

sub test_storage_put_requires_ids {
    my ($storage, $loop, $unloop) = @_;
    note("-------- test_storage_put_requires_ids");
    $loop ||= sub {};
    $unloop ||= sub {};
    my %cases = (
        no_id => status(1),
        undef_id => status(2),
    );
    my $ok_status = status(3);
    delete $cases{no_id}{id};
    $cases{undef_id}{id} = undef;
    my %base = (timeline => '_test_tl_put_requires_ids');
    my $callbacked = 0;
    $storage->delete_statuses(%base, ids => undef, callback => sub {
        my $error = shift;
        is($error, undef, 'delete succeed');
        $callbacked = 1;
        $unloop->();
    });
    $loop->();
    ok($callbacked, 'callbacked');
    foreach my $case (keys %cases) {
        my $s = $cases{$case};
        dies_ok { $storage->put_statuses(%base, mode => 'insert', statuses => $s) } "case: $case, insert, single: dies OK";
        dies_ok { $storage->put_statuses(%base, mode => 'update', statuses => $s) } "case: $case, update, single: dies OK";
        dies_ok { $storage->put_statuses(%base, mode => 'upsert', statuses => $s) } "case: $case, upsert, single: dies OK";
        dies_ok { $storage->put_statuses(%base, mode => 'insert', statuses => [$ok_status, $s]) } "case: $case, insert, array: dies OK";
        dies_ok { $storage->put_statuses(%base, mode => 'update', statuses => [$ok_status, $s]) } "case: $case, update, array: dies OK";
        dies_ok { $storage->put_statuses(%base, mode => 'upsert', statuses => [$ok_status, $s]) } "case: $case, upsert, array: dies OK";
        my $statuses = sync_get($storage, $loop, $unloop, %base, count => 'all');
        is(int(@$statuses), 0, 'storage is empty');
    }
}

=pod

=head1 NAME

BusyBird::Test::StatusStorage - Test routines for StatusStorage

=head1 SYNOPSIS


    use Test::More;
    use BusyBird::Test::StatusStorage qw(:storage);
    
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
If the storage does not use any event loop mechanism, C<$loop> and C<$unloop> can be omitted.

In general test of statuses are based on status IDs.
This allows implementations to modify statuses internally.
In addition, statuses are tested unordered.


=head2 test_storage_ordered($storage, $loop, $unloop)

Test the order of statuses obtained by C<get_statuses()> method.

This test assumes the C<$storage> conforms to the "Order of Statuses" guideline
documented in L<BusyBird::StatusStorage>.
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

=head2 test_storage_missing_arguments($storage, $loop, $unloop)

Test if the C<$storage> throws an exception when a mandatory argument is missing.

The arguments are the same as C<test_storage_common> function.

=head2 test_storage_put_requires_ids($storage, $loop, $unloop)

Test if the C<$storage> throws an exception when some C<statuses> given to C<put_statuses()> method
do not have their C<id> fields.

The arguments are the same as C<test_storage_common> function.

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

