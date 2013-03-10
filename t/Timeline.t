use strict;
use warnings;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use Test::More;
use Test::Builder;
use Test::Exception;
use Test::MockObject;
use BusyBird::Test::StatusStorage qw(:status);
use BusyBird::Test::Timeline_Util qw(sync status *LOOP *UNLOOP);
use Test::Memory::Cycle;
use BusyBird::DateTime::Format;
use BusyBird::Log;
use DateTime;
use Storable qw(dclone);

BEGIN {
    use_ok('BusyBird::Timeline');
    use_ok('BusyBird::StatusStorage::Memory');
    use_ok('BusyBird::Watcher');
}

$BusyBird::Log::LOGGER = undef;

our $CREATE_STORAGE;

sub test_content {
    my ($timeline, $args_ref, $exp, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ($error, $statuses) = sync($timeline, 'get_statuses', %$args_ref);
    is($error, undef, "get_statuses succeed");
    test_status_id_list($statuses, $exp, $msg);
}

sub test_unacked_counts {
    my ($timeline, $exp, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ($error, $got) = sync($timeline, 'get_unacked_counts');
    is($error, undef, "get_unacked_counts succeed");
    is_deeply($got, $exp, $msg);
}

sub test_error_back {
    my (%args) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $timeline = $args{timeline};
    my $method = $args{method};
    my $args = $args{args};
    ## my $error_index = $args{error_index};
    my $exp_error = $args{exp_error};
    my $label = $args{label} || '';
    my ($got_error) = sync($timeline, $method, %$args);
    ok(defined($got_error), "$label: error expected.");
    like($got_error, $exp_error, "$label: error message is as expected.");
}

sub filter {
    my ($timeline, $mode, $sync_filter) = @_;
    if($mode eq 'sync') {
        $timeline->add_filter($sync_filter);
    }elsif($mode eq 'async') {
        $timeline->add_filter(sub {
            my ($statuses, $done) = @_;
            $done->($sync_filter->($statuses));
        }, 1);
    }
}

sub test_sets {
    my ($got_set_array, $exp_set_array, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ($got_set_hash, $exp_set_hash) = map {
        my $a = $_;
        my $h = {};
        $h->{$_}++ foreach @$a;
        $h;
    } ($got_set_array, $exp_set_array);
    is_deeply($got_set_hash, $exp_set_hash, $msg);
}

sub test_watcher_basic {
    my ($watcher) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    isa_ok($watcher, 'BusyBird::Watcher');
    can_ok($watcher, 'active', 'cancel');
}

my $CLASS = 'BusyBird::Timeline';

sub test_timeline {
    {
        note('-- checking names');
        my %s = (storage => $CREATE_STORAGE->());
        dies_ok { $CLASS->new(%s, name => '') } 'NG: empty name';
        my $ng_symbols = '!"#$%&\\(){}[]<>@*+;:.,^~|/?' . "' \t\r\n";
        foreach my $i (0 .. (length($ng_symbols)-1)) {
            my $name = substr($ng_symbols, $i, 1);
            dies_ok { $CLASS->new(%s, name => $name) } "NG: name '$name'";
        }
        dies_ok { $CLASS->new(%s, name => 'space in the middle') } "NG: contains space";
        my $tl;
        lives_ok { $tl = $CLASS->new(%s, name => 'a-zA-Z0-9_-') } "OK: a-zA-Z0-9_-";
        is($tl->name(), 'a-zA-Z0-9_-', 'name OK');
    }

    {
        note('--- status methods');
        my %newbase = (
            storage => $CREATE_STORAGE->(),
        );
        my $timeline = new_ok($CLASS, [%newbase, name => 'test']);
        is($timeline->name(), 'test', 'name OK');
        test_content($timeline, {count => 'all'}, [], 'status is empty');
        test_unacked_counts($timeline, {total => 0});
        my ($error, $ret) = sync($timeline, 'add_statuses', statuses => [map {status($_)} (1..10)]);
        is($error, undef, 'add_statuses succeed');
        is($ret, 10, '10 added');
        test_content($timeline, {count => 'all', ack_state => 'unacked'},
                     [reverse 1..10], '10 unacked');
        test_content($timeline, {count => 'all', ack_state => 'acked'}, [], '0 acked');
        test_unacked_counts($timeline, {total => 10, 0 => 10});
        ($error, $ret) = sync($timeline, 'ack_statuses');
        is($error, undef, 'ack_statuses succeed');
        is($ret, 10, '10 acked');
        test_content($timeline, {count => 'all', ack_state => 'unacked'}, [], '0 unacked');
        test_content($timeline, {count => 'all', ack_state => 'acked'}, [reverse 1..10], '10 acked');
        my $callbacked = 0;
        $timeline->add([map { status($_) } 11..20], sub {
            my ($error, $added_num) = @_;
            is($error, undef, 'add succeed');
            is($added_num, 10, '10 added');
            $callbacked = 1;
            $UNLOOP->();
        });
        $LOOP->();
        ok($callbacked, 'add callbacked');
        test_content($timeline, {count => 'all', ack_state => 'unacked'}, [reverse 11..20], '10 unacked');
        test_content($timeline, {connt => 'all', ack_state => "acked"}, [reverse 1..10], '10 acked');
        test_content($timeline, {count => 10, ack_state => 'any', max_id => 15}, [reverse 6..15], 'get: count and max_id query');
        test_content($timeline, {count => 20, ack_state => 'acked', max_id => 12}, [], 'get: conflicting ack_state and max_id');
        test_content($timeline, {count => 10, ack_state => 'unacked', max_id => 12}, [reverse 11,12], 'get: only unacked');
        ($error, $ret) = sync($timeline, 'ack_statuses', max_id => 15);
        is($error, undef, "ack_statuses succeed");
        is($ret, 5, '5 acked');
        test_content($timeline, {count => 'all', ack_state => 'unacked'}, [reverse 16..20], '5 unacked');
        test_unacked_counts($timeline, {total => 5, 0 => 5});
        ($error, $ret) = sync($timeline, 'delete_statuses', ids => 18);
        is($error, undef, "delete_statuses succeed");
        is($ret, 1, '1 deleted');
        test_content($timeline, {count => 'all', ack_state => 'unacked'}, [reverse 16,17,19,20], '4 unacked');
        test_unacked_counts($timeline, {total => 4, 0 => 4});
        ($error, $ret) = sync($timeline, 'delete_statuses', ids => [15,16,17,18]);
        is($error, undef, "delete_statuses succeed");
        is($ret, 3, '3 deleted');
        test_content($timeline, {count => 'all'}, [reverse 1..14, 19..20], '14 acked, 2 unacked');
        ($error, $ret) = sync($timeline, 'put_statuses', mode => 'insert', statuses => [map {status($_)} 19..22]);
        is($error, undef, "put_statuses succeed");
        is($ret, 2, '2 inserted');
        test_content($timeline, {count => 'all'}, [reverse 1..14, 19..22], '14 acked, 4 unacked');
        test_unacked_counts($timeline, {total => 4, 0 => 4});
        ($error, $ret) = sync($timeline, 'put_statuses', mode => 'update', statuses => [map {status($_, 1)} 13..17]);
        is($error, undef, "put_statuses succeed");
        is($ret, 2, '2 updated');
        test_content($timeline, {count => 'all', ack_state => "unacked"}, [reverse 13,14,19..22], '6 unacked');
        test_content($timeline, {count => 'all', ack_state => "acked"}, [reverse 1..12], '12 acked');
        test_unacked_counts($timeline, {total => 6, 1 => 2, 0 => 4});
        ($error, $ret) = sync($timeline, 'put_statuses', mode => 'upsert', statuses => [map {status($_, 2)} 11..18]);
        is($error, undef, "put_statuses succeed");
        is($ret, 8, '8 upserted');
        test_content($timeline, {count => 'all', ack_state => "unacked"}, [reverse 11..22], '12 unacked');
        test_content($timeline, {count => 'all', ack_state => "acked"}, [reverse 1..10], '10 acked');
        test_unacked_counts($timeline, {total => 12, 2 => 8, 0 => 4});
        ($error, my ($con, $ncon)) = sync($timeline, 'contains', query => 5);
        is($error, undef, "contains succeed");
        is_deeply($con, [5], '5 is contained');
        is_deeply($ncon, [], '5 is contained');
        ($error, $con, $ncon) = sync($timeline, 'contains', query => status(30));
        is($error, undef, "contains succeed");
        is_deeply($con, [], '30 is not contained');
        is_deeply($ncon, [status(30)], '30 is not contained');
        ($error, $con, $ncon) = sync($timeline, 'contains', query => [
            (-5 .. 5), (reverse map {status($_)} 20..25)
        ]);
        is($error, undef, "contains succeed");
        is_deeply($con, [1..5, (reverse map {status($_)} 20..22)], 'contained IDs and statuses OK');
        is_deeply($ncon, [-5..0, (reverse map {status($_)} 23..25)], 'not contained IDs and statuses OK');
        ($error, $ret) = sync($timeline, 'delete_statuses', ids => undef);
        is($error, undef, "delete_statuses succeed");
        is($ret, 22, 'delete all');
        dies_ok { $timeline->contains(callback => sub {}) } 'contains: query is missing';
        dies_ok { $timeline->contains(query => 5) } 'contains: callback is missing';
        test_content($timeline, {count => 'all'}, [], 'all deleted');
        test_unacked_counts($timeline, {total => 0});
    }

    {
        note('--- in case status storage returns errors.');
        my $mock = Test::MockObject->new();
        foreach my $method ('get_unacked_counts', map {"${_}_statuses"} qw(get put ack delete)) {
            $mock->mock($method, sub {
                my ($self, %args) = @_;
                if(defined($args{callback})) {
                    $args{callback}->("error: $method");
                }
            });
        }
        my $timeline = new_ok($CLASS, [name => 'test', storage => $mock]);
        my %t = (timeline => $timeline);
        test_error_back(%t, method => 'get_statuses', args => {count => 'all'}, label => "get",
                        exp_error => qr/get_statuses/);
        test_error_back(%t, method => 'put_statuses',
                        args => {mode => 'insert', statuses => status(1)},
                        label => "put", exp_error => qr/put_statuses/);
        test_error_back(%t, method => 'ack_statuses', args => {}, label => "ack",
                        exp_error => qr/ack_statuses/);
        test_error_back(%t, method => 'delete_statuses', args => {ids => undef}, label => "delete",
                        exp_error => qr/delete_statuses/);
        test_error_back(%t, method => 'get_unacked_counts', args => {}, label => "get_unacked_counts",
                        exp_error => qr/get_unacked_counts/);
        test_error_back(%t, method => 'contains', args => {query => [10,11,12]}, label => "contains",
                        exp_error => qr/get_statuses/);
    }

    {
        note('--- filters: argument spec.');
        my $timeline = new_ok($CLASS, [name => 'test', storage => $CREATE_STORAGE->()]);
        my @in_statuses = (status(1));
        my $callbacked = 0;
        $timeline->add_filter(sub {
            my ($statuses) = @_;
            is_deeply($statuses, \@in_statuses, 'sync: input statuses OK');
            $callbacked++;
            return $statuses;
        });
        $timeline->add_filter(sub {
            my ($statuses, $done) = @_;
            is_deeply($statuses, \@in_statuses, 'async: input statuses OK');
            is(ref($done), 'CODE', 'async: done callback OK');
            $callbacked++;
            $done->($statuses);
        }, 'async');
        $timeline->add(\@in_statuses, sub { $callbacked++;  $UNLOOP->() });
        $LOOP->();
        is($callbacked, 3, '2 filters and finish callback called');
        memory_cycle_ok($timeline, 'timeline does not have cycle-ref.');
    }

    {
        note('--- filters changing statuses');
        foreach my $mode (qw(sync async)) {
            note("--- --- filter mode = $mode");
            my $timeline = new_ok($CLASS, [name => 'test', storage => $CREATE_STORAGE->()]);
            filter($timeline, $mode, sub {
                ## in-place modification
                my $statuses = shift;
                $_->{counter} = [1] foreach @$statuses;
                return $statuses;
            });
            sync($timeline, 'add_statuses', statuses => [status(1)]);
            my ($error, $statuses) = sync($timeline, 'get_statuses', count => 'all');
            is($error, undef, "get_statuses succeed");
            test_status_id_list($statuses, [1], 'IDs OK');
            is_deeply($statuses->[0]{counter}, [1], "filtered.");
            filter($timeline, $mode, sub {
                ## replace original
                my $original = shift;
                my $cloned = dclone($original);
                push(@{$_->{counter}}, 2) foreach @$cloned;
                push(@{$_->{counter}}, 3) foreach @$original;
                return $cloned;
            });
            my $callbacked = 0;
            $timeline->add([map {status($_)} (2,3)], sub {
                my ($error) = @_;
                is($error, undef, "add succeed");
                $callbacked = 1;
                $UNLOOP->();
            });
            $LOOP->();
            ok($callbacked, "callbacked");
            memory_cycle_ok($timeline, 'timeline does not have cycle-ref.');
            ($error, $statuses) = sync($timeline, 'get_statuses', count => 'all');
            is($error, undef, "get_statuses succeed");
            test_status_id_list($statuses, [3,2,1], "IDs OK");
            is_deeply($statuses->[0]{counter}, [1,2], "ID 3, filter OK");
            is_deeply($statuses->[1]{counter}, [1,2], 'ID 2, filter OK');
            is_deeply($statuses->[2]{counter}, [1], 'ID 1 is not changed.');
            filter($timeline, $mode, sub { [] }); ## null filter
            ($error, my ($ret)) = sync($timeline, 'add_statuses', statuses => [map {status($_)} 11..30]);
            is($error, undef, "add_statuses succeed");
            is($ret, 0, 'nothing added because of the null filter');
            ($error, $ret) = sync($timeline, 'put_statuses', mode => 'insert', statuses => status(4));
            is($error, undef, "put_statuses succeed");
            is($ret, 1, 'put_statuses bypasses the filter');
            ($error, $statuses) = sync($timeline, 'get_statuses', count => 'all');
            is($error, undef, "get_statuses succeed");
            test_status_id_list($statuses, [reverse 1..4], "IDs OK");
            ok(!exists($statuses->[0]{counter}), 'ID 4 does not have counter');
            is_deeply($statuses->[1]{counter}, [1,2], "ID 3 is not changed");
            is_deeply($statuses->[2]{counter}, [1,2], 'ID 2 is not changed');
            is_deeply($statuses->[3]{counter}, [1],   'ID 1 is not changed');
            ($error, $ret) = sync($timeline, 'put_statuses', mode => 'update', statuses => [map {status($_)} (1..3)]);
            is($error, undef, "put_statuses succeed");
            is($ret, 3, '3 updated without interference from filters');
            ($error, $statuses) = sync($timeline, 'get_statuses', count => 'all');
            is($error, undef, "get_statuses succeed");
            test_status_id_list($statuses, [reverse 1..4], "IDs OK");
            ok(!exists($statuses->[0]{counter}), 'ID 4 does not have counter');
            ok(!exists($statuses->[1]{counter}), 'ID 3 is updated');
            ok(!exists($statuses->[2]{counter}), 'ID 2 is updated');
            ok(!exists($statuses->[3]{counter}), 'ID 1 is updated');

            foreach my $case (
                {name => 'integer', junk => 10},
                {name => 'undef', junk => undef},
                {name => 'hash-ref', junk => {}},
                {name => 'code-ref', junk => sub {}},
            ) {
                note("--- --- filter mode = $mode: junk filter: $case->{name}");
                my @log = ();
                local $BusyBird::Log::LOGGER = sub { push(@log, [@_]) };
                my $timeline = new_ok($CLASS, [
                    name => 'test',
                    storage => $CREATE_STORAGE->(),
                ]);
                filter($timeline, $mode, sub { return $case->{junk} });
                ($error, $ret) = sync($timeline, 'add_statuses', statuses => [status(1)]);
                is($error, undef, "add_statuses succeed");
                is($ret, 1, "add 1 status");
                cmp_ok(int(grep { $_->[0] =~ /warn/i } @log), '>=', 1, 'at least 1 warning is logged.');
                ($error, $statuses) = sync($timeline, 'get_statuses', count => 'all');
                is($error, undef, "get_statuses succeed");
                test_status_id_list($statuses, [1], "status OK");
            }
        }
    }

    {
        note('--- mixed sync/async filters. concurrency regulation.');
        my $timeline = new_ok($CLASS, [
            name => 'test', storage => $CREATE_STORAGE->(),
        ]);
        my @triggers = ([], []);
        my $trigger_counts = sub { [ map { int(@$_) } @triggers ] };
        $timeline->add_filter(sub {
            my $s = shift;
            $_->{counter} = [1] foreach @$s;
            return $s;
        });
        $timeline->add_filter_async(sub {
            my ($s, $done) = @_;
            push(@{$_->{counter}}, 2) foreach @$s;
            push(@{$triggers[0]}, sub { $done->($s) });
        });
        $timeline->add_filter(sub {
            my $s = shift;
            push(@{$_->{counter}}, 3) foreach @$s;
            return $s;
        });
        $timeline->add_filter_async(sub {
            my ($s, $done) = @_;
            push(@{$_->{counter}}, 4) foreach @$s;
            push(@{$triggers[1]}, sub { $done->($s) });
        });
    
        my @done = ();
        foreach my $id (1, 2) {
            $timeline->add([status($id)], sub {
                push(@done, $id);
                $UNLOOP->();
            });
        }
        memory_cycle_exists($timeline, 'there IS cyclic refs while a status is flowing in filters.');
        is_deeply(\@done, [], "none of the additions is complete.");
        is_deeply($trigger_counts->(), [1, 0], 'only 1 trigger. concurrency is regulated.');
        shift(@{$triggers[0]})->();
        is_deeply($trigger_counts->(), [0, 1], 'move to next trigger.');
        shift(@{$triggers[1]})->();
        $LOOP->();
        is_deeply($trigger_counts->(), [1, 0], 'next status is in the filter.');
        is_deeply(\@done, [1], 'ID 1 is complete');
        shift(@{$triggers[0]})->();
        is_deeply($trigger_counts->(), [0, 1], 'move to next trigger');
        shift(@{$triggers[1]})->();
        $LOOP->();
        is_deeply($trigger_counts->(), [0, 0], 'no more status');
        is_deeply(\@done, [1, 2], "all complete");
        memory_cycle_ok($timeline, "there is no cyclic refs once it completes all addtions.");
        my ($error, $statuses) = sync($timeline, 'get_statuses', count => 'all');
        is($error, undef, "get_statuses succeed");
        test_status_id_list($statuses, [2, 1], "IDs OK");
        foreach my $s (@$statuses) {
            is_deeply($s->{counter}, [1,2,3,4], "ID $s->{id} counter OK");
        }
    }

    {
        note('--- filter should not change the original status objects');
        my $timeline = new_ok($CLASS, [name => 'test', storage => $CREATE_STORAGE->()]);
        $timeline->add_filter(sub {
            my ($statuses) = @_;
            $_->{added_field} = 1 foreach @$statuses;
            return $statuses;
        });
        my $s = status(1);
        $timeline->add([$s], sub { $UNLOOP->() });
        $LOOP->();
        ok(!defined($s->{added_field}), "original status does not have added_field.");
        my ($error, $results) = sync($timeline, 'get_statuses', count => 'all');
        is($error, undef, "get_statuses succeed");
        test_status_id_list($results, [1], "status ID ok");
        is($results->[0]{added_field}, 1, "added_field ok");
    }

    {
        note('--- watch_unacked_counts');
        my $timeline = new_ok($CLASS, [name => 'test', storage => $CREATE_STORAGE->()]);
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        note('--- -- watch immediate: total 0');
        my $test_case = sub {
            my ($case, $exp_current_unacked_counts) = @_;
            local $Test::Builder::Level = $Test::Builder::Level + 1;
            my $callbacked = 0;
            my $label = $case->{label};
            my $inside_w;
            my $watcher = $timeline->watch_unacked_counts(assumed => $case->{watch}, callback => sub {
                my ($error, $w, $unacked_counts) = @_;
                is($error, undef, "$label: succeed.");
                $callbacked = 1;
                is_deeply($unacked_counts, $exp_current_unacked_counts, "$label: unacked counts OK");
                $w->cancel();
                $inside_w = $w;
            });
            test_watcher_basic($watcher);
            is($callbacked, $case->{exp_callback}, "$label: callback is OK");
            if($callbacked) {
                is($inside_w, $watcher, "$label: watcher inside is the same as watcher outside");
            }
            $watcher->cancel();
        };
        foreach my $case (
            {label => '1 total', watch => {total => 1}, exp_callback => 1},
            {label => '0 total, 3 level.1', watch => {total => 0, 1 => 3}, exp_callback => 1},
            {label => 'no total, 4 level.2', watch => {2 => 4}, exp_callback => 1},
            {label => 'empty', watch => {}, exp_callback => 1},
            {label => '0 total', watch => {total => 0}, exp_callback => 0},
            {label => 'no total, 0 level.4', watch => {4 => 0}, exp_callback => 0},
            {label => '0 levels.2,3', watch => {2 => 0, 3 => 0}, exp_callback => 0},
            {label => 'only junk 0', watch => {junk => 0}, exp_callback => 1},
            {label => 'junks with total 0', watch => {total => 0, junk1 => 1, _ => 101293}, exp_callback => 0},
            {label => 'junks with total 1', watch => {total => 1, _ => 0}, exp_callback => 1}
        ) {
            $test_case->($case, {total => 0});
        }
        sync($timeline, 'add_statuses',
             statuses => [status(0,0), status(1,1), status(2,2)]);
        sync($timeline, 'ack_statuses');
        sync($timeline, 'add_statuses',
             statuses => [status(3), status(4,1), status(5,2), status(6,0)]);
        sync($timeline, 'get_statuses', count => 1); ## go into event loop to update unacked_counts cache.
        note('--- -- watch immediate: some on 3 levels, some acked.');
        foreach my $case (
            {label => '0 total', watch => {total => 0}, exp_callback => 1},
            {label => 'empty', watch => {}, exp_callback => 1},
            {label => 'single diff', watch => {total => 4, 0 => 1, 1 => 1, 2 => 1}, exp_callback => 1},
            {label => 'all up-to-date', watch => {total => 4, 0 => 2, 1 => 1, 2 => 1}, exp_callback => 0},
            {label => 'only total diff', watch => {total => 2}, exp_callback => 1},
            {label => 'only level.2', watch => {2 => 1}, exp_callback => 0},
            {label => 'levels.0,2 up-to-date', watch => {0 => 2, 2 => 1}, exp_callback => 0},
            {label => '0 irrelevant levels', watch => {10 => 0, 32 => 0, -10 => 0}, exp_callback => 0},
            {label => 'correct levels with junk', watch => {0 => 2, 1 => 1, _ => 1192}, exp_callback => 0},
            {label => 'wrong levels with junks 0', watch => {total => 3, 2 => 1, junk1 => 0, _ => 0}, exp_callback => 1},
        ) {
            $test_case->($case, {total => 4, 0 => 2, 1 => 1, 2 => 1});
        }
        note('--- -- watch immediate: negative level');
        sync($timeline, 'add_statuses', statuses => [status(7, -3)]);
        sync($timeline, 'get_statuses', count => 1); ## go into event loop to update unacked_counts.
        foreach my $case (
            {label => '0 total', watch => {total => 0}, exp_callback => 1},
            {label => '-3 OK', watch => {-3 => 1}, exp_callback => 0},
            {label => '-3 and 1 OK', watch => {-3 => 1, 1 => 1}, exp_callback => 0},
            {label => 'empty', watch => {}, exp_callback => 1},
            {label => '-3 wrong', watch => {-3 => 5}, exp_callback => 1},
        ) {
            $test_case->($case, {total => 5, -3 => 1, 0 => 2, 1 => 1, 2 => 1});
        }
    }

    {
        note('--- -- watch delayed. add, ack, put, delete');
        my $timeline = new_ok($CLASS, [name => 'test', storage => $CREATE_STORAGE->()]);
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        my $callbacked = 0;
        my $result;
        my $watch = sub {
            my (%watch_spec) = @_;
            $timeline->watch_unacked_counts(assumed => \%watch_spec, callback => sub {
                my ($error, $w, $unacked_counts) = @_;
                is($error, undef, "watch_unacked_counts succeed.");
                $result = $unacked_counts;
                $callbacked = 1;
                $w->cancel();
            });
        };
        $watch->(total => 0);
        ok(!$callbacked, "not callbacked yet");
        sync($timeline, 'add_statuses', statuses => [status(1), status(2,1)]);
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        ok($callbacked, 'callbacked');
        is_deeply($result, {total => 2, 0 => 1, 1 => 1}, "result OK");

        $callbacked = 0;
        undef $result;
        $watch->(total => 2);
        ok(!$callbacked, 'not callbacked yet');
        sync($timeline, 'ack_statuses');
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        ok($callbacked, 'callbacked');
        is_deeply($result, {total => 0}, "result OK");

        $callbacked = 0;
        undef $result;
        $watch->(2 => 0);
        ok(!$callbacked, 'not callbacked yet');
        sync($timeline, 'put_statuses', mode => 'insert', statuses => status(3,2));
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        ok($callbacked, 'callbacked');
        is_deeply($result, {total => 1, 2 => 1}, 'result OK');

        $callbacked = 0;
        undef $result;
        $watch->(1 => 0, 2 => 1);
        ok(!$callbacked, 'not callbacked yet');
        sync($timeline, 'put_statuses', mode => 'update', statuses => status(2,1));
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        ok($callbacked, 'callbacked');
        is_deeply($result, {total => 2, 1 => 1, 2 => 1}, "result OK");
    
        $callbacked = 0;
        undef $result;
        $watch->(3 => 0);
        ok(!$callbacked, 'not callbacked yet');
        sync($timeline, 'put_statuses', mode => 'upsert', statuses => [status(4,3), status(1)]);
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        ok($callbacked, 'callbacked');
        is_deeply($result, {total => 4, 0 => 1, 1 => 1, 2 => 1, 3 => 1}, "result OK");

        $callbacked = 0;
        undef $result;
        $watch->(total => 4, 2 => 1);
        ok(!$callbacked, 'not callbacked yet');
        sync($timeline, 'delete_statuses', ids => 4);
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        ok($callbacked, 'callbacked');
        is_deeply($result, {total => 3, 0 => 1, 1 => 1, 2 => 1}, "result OK");

        note('--- -- watch delayed. put(update) to change levels.');
        $callbacked = 0;
        undef $result;
        $watch->(total => 3);
        ok(!$callbacked, 'not callbacked yet');
        sync($timeline, "put_statuses", mode => 'update', statuses => status(1,1));
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        ok(!$callbacked, 'not callbacked yet');
        sync($timeline, "delete_statuses", ids => 3);
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        ok($callbacked, "callbacked");
        is_deeply($result, {total => 2, 1 => 2}, "result OK");

    }

    {
        my $timeline = new_ok($CLASS, [name => 'test', storage => $CREATE_STORAGE->()]);
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        $timeline->add_filter(sub { [] }); ## null filter
        my $callbacked = 0;
        my $result;
        my $nowstring  = BusyBird::DateTime::Format->format_datetime(
            DateTime->now(time_zone => 'UTC')
        );
        my $watcher = $timeline->watch_unacked_counts(assumed => {total => 0}, callback => sub {
            my ($error, $w, $unacked_counts) = @_;
            is($error, undef, "watch_unacked_counts succeed");
            $callbacked = 1;
            $result = $unacked_counts;
            $w->cancel();
        });
        ok(!$callbacked, 'not callbacked yet');
        my @statuses = map { my $s = status($_); $s->{busybird}{acked_at} = $nowstring; $s } 1..3;
        my ($error, $put_result) = sync($timeline, 'put_statuses', mode => 'insert', statuses => \@statuses);
        is($error, undef, "put_statuses succeed");
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        is($put_result, 3, "3 statuses put");
        ok(!$callbacked, 'not callbacked because the inserted statuses are already acked.');
        ($error, my ($add_result)) = sync($timeline, 'add_statuses', statuses => [status(5)]);
        is($error, undef, "add_statuses succeed");
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        is($add_result, 0, '0 status added, because of null filter');
        ok(!$callbacked, 'not callbacked because of null filter');
        ($error, $put_result) = sync($timeline, 'put_statuses', mode => 'update', statuses => status(2,5));
        is($error, undef, "put_statuses succeed");
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        is($put_result, 1, '1 status updated');
        ok($callbacked, 'callbacked');
        is_deeply($result, {total => 1, 5 => 1}, "result OK");
        ok(!$watcher->active, 'watcher is now inactive');
        memory_cycle_ok($timeline, 'no cyclic ref in timeline');
    }

    {
        note('--- watch_unacked_counts - persistent watcher');
        my $timeline = new_ok($CLASS, [name => 'test', storage => $CREATE_STORAGE->()]);
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        my $callbacked = 0;
        my $watcher = $timeline->watch_unacked_counts(assumed => {total => 1}, callback => sub {
            my ($error, $w, $unacked_counts) = @_;
            is($error, undef, "watch_unacked_counts succeed");
            $callbacked++;
        });
        is($callbacked, 1, '1 callbacked');
        ok($watcher->active, 'watcher still active');
        my ($error, $add_count) = sync($timeline, 'add_statuses', statuses => [status(1)]);
        is($error, undef, "add_statuses succeed");
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        is($add_count, 1, '1 added');
        is($callbacked, 1, 'no callback at this addition');
        ($error, $add_count) = sync($timeline, 'add_statuses', statuses => [status(2)]);
        is($error, undef, "add_statuses succeed");
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        is($add_count, 1, '1 added');
        is($callbacked, 2, 'callbacked again');
        $watcher->cancel;
        memory_cycle_ok($timeline, 'no cyclic ref in timeline');
        ($error, $add_count) = sync($timeline, 'add_statuses', statuses => [status(3)]);
        is($error, undef, "add_statuses succeed");
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        is($add_count, 1, '1 added');
        is($callbacked, 2, 'not callbacked anymore');
    }

    {
        note('--- watch_unacked_counts - watcher quota');
        my $timeline = new_ok($CLASS, [
            name => 'test', storage => $CREATE_STORAGE->(),
            watcher_max => 3
        ]);
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        my @watchers = ();
        my @results = ();
        foreach my $i (0..2) {
            my $watcher = $timeline->watch_unacked_counts(assumed => {total => 0}, callback => sub {
                push(@results, [$i, @_]);
            });
            ok($watcher->active, "watcher $i is active.");
            push(@watchers, $watcher);
        }
        {
            my $new_watcher = $timeline->watch_unacked_counts(assumed => {2 => 0}, callback => sub {
                push(@results, [3, @_]);
            });
            ok($new_watcher->active, "watcher 3 is active");
            push(@watchers, $new_watcher);
        }
        ok(!$watchers[0]->active, 'now watcher 0 is inactive because it is cancelled by the quota');
        is(int(@results), 1, "got 1 result");
        is($results[0][0], 0, '... it is from watcher 0');
        ok(defined($results[0][1]), '... it indicates error');
    
        @results = ();
        sync($timeline, 'add_statuses', statuses => [status(0)]);
        sync($timeline, 'get_statuses', count => 1); ## go into event loop
        is(int(@results), 2, 'got 2 results');
        test_sets([$results[0][0], $results[1][0]], [1,2], "... they are from watchers 1,2");
        foreach my $r (@results) {
            is($r->[1], undef, "... callback succeed");
            is_deeply($r->[3], {total => 1, 0 => 1}, "... unacked counts OK");
        }
        $_->cancel foreach @watchers[1,2];

        @results = ();
        {
            my $watcher = $timeline->watch_unacked_counts(assumed => {2 => 0}, callback => sub { push(@results, [4, @_]) });
            ok($watcher->active, 'watcher 4 is active');
            push(@watchers, $watcher);
        }
        is(int(@results), 0, 'no watcher fires yet');
        foreach my $lv0_count (1..4) {
            @results = ();
            my $watcher = $timeline->watch_unacked_counts(assumed => {0 => $lv0_count}, callback => sub { push(@results, [-1, @_]) });
            is(int(@results), 0, "lv0_count = $lv0_count: no watcher fired");
            sync($timeline, 'add_statuses', statuses => [status($lv0_count)]);
            sync($timeline, 'get_statuses', count => 1); ## go into event loop
            is(int(@results), 1, "lv0_count != $lv0_count: 1 watcher fired");
            is($results[0][0], -1, "... and it's the ephemeral watcher");
            is($results[0][1], undef, "... and it succeeded");
            is_deeply($results[0][3], {total => $lv0_count + 1, 0 => $lv0_count + 1}, "... unacked counts OK");
            $watcher->cancel();
        }

        @results = ();
        {
            my $watcher = $timeline->watch_unacked_counts(assumed => {0 => 5}, callback => sub { push(@results, [5, @_]) });
            push(@watchers, $watcher);
            is(int(@results), 0, "watcher 5 added. no watcher fired.");

            $watcher = $timeline->watch_unacked_counts(assumed => {total => 0}, callback => sub { push(@results, [-1, @_]); $_[0]->cancel() });
            ok(!$watcher->active, "the ephemeral watcher immediately fired and became inactive.");
            is(int(@results), 1, "... in this case, the quota does nothing to pending watchers.");
            is($results[0][0], -1, "... only the ephemeral watcher fired.");
            is($results[0][1], undef, "... and it's success");
            is_deeply($results[0][3], {total => 5, 0 => 5}, "... unacked counts OK");
        }

        @results = ();
        {
            my $watcher = $timeline->watch_unacked_counts(assumed => {total => 5}, callback => sub { push(@results, [6, @_]); $_[0]->cancel() });
            ok($watcher->active, "watcher 6 is active.");
            push(@watchers, $watcher);
            is(int(@results), 1, "1 watcher is cancelled by the quota because it is too old.");
            ok($results[0][0] == 3 || $results[0][0] == 4, "the canceled is watcher 3 or 4. They are both too old, so either one of them is canceled.");
            ok(defined($results[0][1]), "the result indicates error");
            my $canceled = $results[0][0];
            my $not_canceled = $canceled == 3 ? 4 : 3;
            ok(!$watchers[$canceled]->active, "watcher $canceled is inactive");
            ok( $watchers[$not_canceled]->active, "watcher $not_canceled is inactive");
            ok( $watchers[5]->active, "watcher 5 is active");
            $watchers[$not_canceled]->cancel;
            $watchers[5]->cancel;
            $watcher->cancel;
        }
        memory_cycle_ok($timeline, "no cyclic ref when all watchers are released.");
    }

    {
        note('--- restore timeline when created ');
        my $storage = $CREATE_STORAGE->();
        my $timeline = new_ok($CLASS, [name => 'hoge', storage => $storage]);
        sync($timeline, 'add_statuses', statuses => [status(1,0)]);
        sync($timeline, 'ack_statuses');
        sync($timeline, 'add_statuses', statuses => [status(2,1), status(3,2)]);

        $timeline = new_ok($CLASS, [name => 'hoge', storage => $storage]);
        test_content($timeline, {count => 'all'}, [3,2,1], 'any statuses OK');
        test_content($timeline, {count => 'all', ack_state => 'acked'}, [1], 'acked statuses OK');
        test_content($timeline, {count => 'all', ack_state => 'unacked'}, [3,2], 'unacked statuses OK');
    
        my $callbacked = 0;
        $timeline->watch_unacked_counts(assumed => {total => 0}, callback => sub {
            my ($error, $w, $unacked_counts) = @_;
            is($error, undef, 'watch succeed');
            is_deeply($unacked_counts, { total => 2, 1 => 1, 2 => 1 }, 'unacked_counts OK');
            $callbacked = 1;
            $w->cancel();
        });
        ok($callbacked, 'callbacked');

        test_unacked_counts($timeline, { total => 2, 1 => 1, 2 => 1}, 'unacked_counts OK');
    }
    {
        note('--- junk to watch_unacked_counts');
        my $timeline = new_ok($CLASS, [name => 'test', storage => $CREATE_STORAGE->()]);
        foreach my $assumed_case (
            {label => "omit"}, {label => "undef", arg => undef}, {label => "string", arg => "hoge"},
            {label => "array-ref", arg => []}, {label => "code-ref", arg => sub {}}
        ) {
            foreach my $callback_case (
                {label => "omit"}, {label => "undef", arg => undef}, {label => "string", arg => "foobar"},
                {label => "array-ref", arg => []}, {label => "hash-ref", arg => {}}
            ) {
                my %args = ();
                $args{assumed} = $assumed_case->{arg} if exists $assumed_case->{arg};
                $args{callback} = $callback_case->{arg} if exists $callback_case->{arg};
                my $label = "assumed: $assumed_case->{label}, callback: $callback_case->{label}";
                dies_ok { $timeline->watch_unacked_counts(%args) } "$label: watch_unacked_counts throws an exception.";
            }
        }
    }
}

{
    note('---------- sync storage');
    local $LOOP = sub {};
    local $UNLOOP = sub {};
    local $CREATE_STORAGE = sub { BusyBird::StatusStorage::Memory->new };
    test_timeline();
}

{
    local $@;
    eval('use BusyBird::Test::StatusStorage::AEDelayed');
    if($@) {
        diag("SKIP: Error while loading AEDelayed: $@");
    }else {
        note('---------- async storage');
        my $cv;
        local $LOOP = sub {
            $cv = AnyEvent->condvar if not defined($cv);
            $cv->recv;
            undef $cv;
        };
        local $UNLOOP = sub {
            $cv = AnyEvent->condvar if not defined($cv);
            $cv->send;
        };
        local $CREATE_STORAGE = sub {
            BusyBird::Test::StatusStorage::AEDelayed->new(
                backend => BusyBird::StatusStorage::Memory->new,
                delay_sec => 0
            );
        };
        test_timeline();
    }
}

done_testing();

