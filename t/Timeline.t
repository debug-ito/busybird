use strict;
use warnings;
use Test::More;
use Test::Builder;
use Test::Exception;
use Test::MockObject;
use Test::BusyBird::StatusStorage qw(:status);
use App::BusyBird::DateTime::Format;
use App::BusyBird::Log;
use DateTime;
use Storable qw(dclone);

BEGIN {
    use_ok('App::BusyBird::Timeline');
    use_ok('App::BusyBird::StatusStorage::Memory');
}

$App::BusyBird::Log::LOGGER = undef;

my $LOOP = sub {};
my $UNLOOP = sub {};

sub create_storage {
    return App::BusyBird::StatusStorage::Memory->new;
}

sub sync {
    my ($timeline, $method, %args) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $callbacked = 0;
    my @result;
    $timeline->$method(%args, callback => sub {
        @result = @_;
        $callbacked = 1;
        $UNLOOP->();
    });
    $LOOP->();
    ok($callbacked, "sync $method callbacked.");
    return @result;
}

sub status {
    my ($id, $level) = @_;
    my %level_elem = defined($level) ? (busybird => { level => $level }) : ();
    return {
        id => $id,
        created_at => App::BusyBird::DateTime::Format->format_datetime(
            DateTime->from_epoch(epoch => $id, time_zone => 'UTC')
        ),
        %level_elem
    };
}

sub test_content {
    my ($timeline, $args_ref, $exp, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ($statuses) = sync($timeline, 'get_statuses', %$args_ref);
    test_status_id_list($statuses, $exp, $msg);
}

sub test_unacked_counts {
    my ($timeline, $exp, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ($got) = sync($timeline, 'get_unacked_counts');
    is_deeply($got, $exp, $msg);
}

sub test_error_back {
    my (%args) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $timeline = $args{timeline};
    my $method = $args{method};
    my $args = $args{args};
    my $error_index = $args{error_index};
    my $exp_error = $args{exp_error};
    my $label = $args{label} || '';
    my @result = sync($timeline, $method, %$args);
    cmp_ok(int(@result), ">", $error_index, "$label: error expected.");
    like($result[$error_index], $exp_error, "$label: error message is as expected.");
}

sub filter {
    my ($timeline, $mode, $sync_filter) = @_;
    my $method;
    my $filter;
    if($mode eq 'sync') {
        $method = 'add_filter';
        $filter = $sync_filter;
    }elsif($mode eq 'async') {
        $method = 'add_filter_async';
        $filter = sub {
            my ($statuses, $done) = @_;
            $done->($sync_filter->($statuses));
        };
    }
    $timeline->$method($filter);
}

my $CLASS = 'App::BusyBird::Timeline';

{
    note('-- checking names');
    my %s = (storage => create_storage());
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
        storage => create_storage(),
    );
    my $timeline = new_ok($CLASS, [%newbase, name => 'test']);
    is($timeline->name(), 'test', 'name OK');
    test_content($timeline, {count => 'all'}, [], 'status is empty');
    test_unacked_counts($timeline, {total => 0});
    my ($ret) = sync($timeline, 'add_statuses', statuses => [map {status($_)} (1..10)]);
    is($ret, 10, '10 added');
    test_content($timeline, {count => 'all', ack_state => 'unacked'},
                 [reverse 1..10], '10 unacked');
    test_content($timeline, {count => 'all', ack_state => 'acked'}, [], '0 acked');
    test_unacked_counts($timeline, {total => 10, 0 => 10});
    ($ret) = sync($timeline, 'ack_statuses');
    is($ret, 10, '10 acked');
    test_content($timeline, {count => 'all', ack_state => 'unacked'}, [], '0 unacked');
    test_content($timeline, {count => 'all', ack_state => 'acked'}, [reverse 1..10], '10 acked');
    my $callbacked = 0;
    $timeline->add([map { status($_) } 11..20], sub {
        my ($added_num, $error) = @_;
        is(int(@_), 1, 'add succeed');
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
    ($ret) = sync($timeline, 'ack_statuses', max_id => 15);
    is($ret, 5, '5 acked');
    test_content($timeline, {count => 'all', ack_state => 'unacked'}, [reverse 16..20], '5 unacked');
    test_unacked_counts($timeline, {total => 5, 0 => 5});
    ($ret) = sync($timeline, 'delete_statuses', ids => 18);
    is($ret, 1, '1 deleted');
    test_content($timeline, {count => 'all', ack_state => 'unacked'}, [reverse 16,17,19,20], '4 unacked');
    test_unacked_counts($timeline, {total => 4, 0 => 4});
    ($ret) = sync($timeline, 'delete_statuses', ids => [15,16,17,18]);
    is($ret, 3, '3 deleted');
    test_content($timeline, {count => 'all'}, [reverse 1..14, 19..20], '14 acked, 2 unacked');
    ($ret) = sync($timeline, 'put_statuses', mode => 'insert', statuses => [map {status($_)} 19..22]);
    is($ret, 2, '2 inserted');
    test_content($timeline, {count => 'all'}, [reverse 1..14, 19..22], '14 acked, 4 unacked');
    test_unacked_counts($timeline, {total => 4, 0 => 4});
    ($ret) = sync($timeline, 'put_statuses', mode => 'update', statuses => [map {status($_, 1)} 13..17]);
    is($ret, 2, '2 updated');
    test_content($timeline, {count => 'all', ack_state => "unacked"}, [reverse 13,14,19..22], '6 unacked');
    test_content($timeline, {count => 'all', ack_state => "acked"}, [reverse 1..12], '12 acked');
    test_unacked_counts($timeline, {total => 6, 1 => 2, 0 => 4});
    ($ret) = sync($timeline, 'put_statuses', mode => 'upsert', statuses => [map {status($_, 2)} 11..18]);
    is($ret, 8, '8 upserted');
    test_content($timeline, {count => 'all', ack_state => "unacked"}, [reverse 11..22], '12 unacked');
    test_content($timeline, {count => 'all', ack_state => "acked"}, [reverse 1..10], '10 acked');
    test_unacked_counts($timeline, {total => 12, 2 => 8, 0 => 4});
    my ($con, $ncon) = sync($timeline, 'contains', query => 5);
    is_deeply($con, [5], '5 is contained');
    is_deeply($ncon, [], '5 is contained');
    ($con, $ncon) = sync($timeline, 'contains', query => status(30));
    is_deeply($con, [], '30 is not contained');
    is_deeply($ncon, [status(30)], '30 is not contained');
    ($con, $ncon) = sync($timeline, 'contains', query => [
        (-5 .. 5), (reverse map {status($_)} 20..25)
    ]);
    is_deeply($con, [1..5, (reverse map {status($_)} 20..22)], 'contained IDs and statuses OK');
    is_deeply($ncon, [-5..0, (reverse map {status($_)} 23..25)], 'not contained IDs and statuses OK');
    ($ret) = sync($timeline, 'delete_statuses', ids => undef);
    dies_ok { $timeline->contains(callback => sub {}) } 'contains: query is missing';
    dies_ok { $timeline->contains(query => 5) } 'contains: callback is missing';
    is($ret, 22, 'delete all');
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
                $args{callback}->(undef, "error: $method");
            }
        });
    }
    my $timeline = new_ok($CLASS, [name => 'test', storage => $mock]);
    my %t = (timeline => $timeline);
    test_error_back(%t, method => 'get_statuses', args => {count => 'all'}, label => "get",
                    error_index => 1, exp_error => qr/get_statuses/);
    test_error_back(%t, method => 'put_statuses',
                    args => {mode => 'insert', statuses => status(1)},
                    label => "put",
                    error_index => 1, exp_error => qr/put_statuses/);
    test_error_back(%t, method => 'ack_statuses', args => {}, label => "ack",
                    error_index => 1, exp_error => qr/ack_statuses/);
    test_error_back(%t, method => 'delete_statuses', args => {ids => undef}, label => "delete",
                    error_index => 1, exp_error => qr/delete_statuses/);
    test_error_back(%t, method => 'get_unacked_counts', args => {}, label => "get_unacked_counts",
                    error_index => 1, exp_error => qr/get_unacked_counts/);
    test_error_back(%t, method => 'contains', args => {query => [10,11,12]}, label => "contains",
                    error_index => 2, exp_error => qr/get_statuses/);
}

{
    note('--- filters: argument spec.');
    my $timeline = new_ok($CLASS, [name => 'test', storage => create_storage()]);
    my @in_statuses = (status(1));
    my $callbacked = 0;
    $timeline->add_filter(sub {
        my ($statuses, $tl) = @_;
        is_deeply($statuses, \@in_statuses, 'sync: input statuses OK');
        is($tl, $timeline, "sync: input timeline OK");
        $callbacked++;
        return $statuses;
    });
    $timeline->add_filter(sub {
        my ($statuses, $tl, $done) = @_;
        is_deeply($statuses, \@in_statuses, 'async: input statuses OK');
        is($tl, $timeline, 'async: input timeline OK');
        is(ref($done), 'CODE', 'async: done callback OK');
        $callbacked++;
        $done->($statuses);
    }, 'async');
    $timeline->add(\@in_statuses, sub { $callbacked++;  $UNLOOP->() });
    $LOOP->();
    is($callbacked, 3, '2 filters and finish callback called');
}

{
    note('--- filters changing statuses');
    foreach my $mode (qw(sync async)) {
        note("--- --- filter mode = $mode");
        my $timeline = new_ok($CLASS, [name => 'test', storage => create_storage()]);
        filter($timeline, $mode, sub {
            ## in-place modification
            my $statuses = shift;
            $_->{counter} = [1] foreach @$statuses;
            return $statuses;
        });
        sync($timeline, 'add_statuses', statuses => status(1));
        my ($statuses) = sync($timeline, 'get_statuses', count => 'all');
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
            $callbacked = 1;
            $UNLOOP->();
        });
        $LOOP->();
        ok($callbacked, "callbacked");
        ($statuses) = sync($timeline, 'get_statuses', count => 'all');
        test_status_id_list($statuses, [3,2,1], "IDs OK");
        is_deeply($statuses->[0]{counter}, [1,2], "ID 3, filter OK");
        is_deeply($statuses->[1]{counter}, [1,2], 'ID 2, filter OK');
        is_deeply($statuses->[2]{counter}, [1], 'ID 1 is not changed.');
        filter($timeline, $mode, sub { [] }); ## null filter
        my ($ret) = sync($timeline, 'add_statuses', statuses => [map {status($_)} 11..30]);
        is($ret, 0, 'nothing added because of the null filter');
        ($ret) = sync($timeline, 'put_statuses', mode => 'insert', statuses => status(4));
        is($ret, 1, 'put_statuses bypasses the filter');
        ($statuses) = sync($timeline, 'get_statuses', count => 'all');
        test_status_id_list($statuses, [reverse 1..4], "IDs OK");
        ok(!exists($statuses->[0]{counter}), 'ID 4 does not have counter');
        is_deeply($statuses->[1]{counter}, [1,2], "ID 3 is not changed");
        is_deeply($statuses->[2]{counter}, [1,2], 'ID 2 is not changed');
        is_deeply($statuses->[3]{counter}, [1],   'ID 1 is not changed');
        ($ret) = sync($timeline, 'put_statuses', mode => 'update', statuses => [map {status($_)} (1..3)]);
        is($ret, 3, '3 updated without interference from filters');
        ($statuses) = sync($timeline, 'get_statuses', count => 'all');
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
            local $App::BusyBird::Log::LOGGER = sub { push(@log, [@_]) };
            my $timeline = new_ok($CLASS, [
                name => 'test',
                storage => create_storage(),
            ]);
            filter($timeline, $mode, sub { return $case->{junk} });
            ($ret) = sync($timeline, 'add_statuses', statuses => status(1));
            is($ret, 1, "add succeed");
            cmp_ok(int(grep { $_->[0] =~ /warn/i } @log), '>=', 1, 'at least 1 warning is logged.');
            ($statuses) = sync($timeline, 'get_statuses', count => 'all');
            test_status_id_list($statuses, [1], "status OK");
        }
    }
}

{
    note('--- mixed sync/async filters. concurrency regulation.');
    my $timeline = new_ok($CLASS, [
        name => 'test', storage => create_storage(),
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
        $timeline->add(status($id), sub {
            push(@done, $id);
        });
    }
    is_deeply(\@done, [], "none of the additions is complete.");
    is_deeply($trigger_counts->(), [1, 0], 'only 1 trigger. concurrency is regulated.');
    shift(@{$triggers[0]})->();
    is_deeply($trigger_counts->(), [0, 1], 'move to next trigger.');
    shift(@{$triggers[1]})->();
    is_deeply($trigger_counts->(), [1, 0], 'next status is in the filter.');
    is_deeply(\@done, [1], 'ID 1 is complete');
    shift(@{$triggers[0]})->();
    is_deeply($trigger_counts->(), [0, 1], 'move to next trigger');
    shift(@{$triggers[1]})->();
    is_deeply($trigger_counts->(), [0, 0], 'no more status');
    is_deeply(\@done, [1, 2], "all complete");
    my ($statuses) = sync($timeline, 'get_statuses', count => 'all');
    test_status_id_list($statuses, [2, 1], "IDs OK");
    foreach my $s (@$statuses) {
        is_deeply($s->{counter}, [1,2,3,4], "ID $s->{id} counter OK");
    }
}

{
    note('--- filter should not change the original status objects');
    my $timeline = new_ok($CLASS, [name => 'test', storage => create_storage()]);
    $timeline->add_filter(sub {
        my ($statuses) = @_;
        $_->{added_field} = 1 foreach @$statuses;
        return $statuses;
    });
    my $s = status(1);
    $timeline->add([$s], sub { $UNLOOP->() });
    $LOOP->();
    ok(!defined($s->{added_field}), "original status does not have added_field.");
    my ($results) = sync($timeline, 'get_statuses', count => 'all');
    test_status_id_list($results, [1], "status ID ok");
    is($results->[0]{added_field}, 1, "added_field ok");
}

TODO: {
    local $TODO = "I will write these tests. I swear.";
    fail('todo: timeline is properly destroyed. no cyclic reference between resource provider (see 2013/01/27)');
    fail('todo: watch_updates for add, ack, put, delete.');
}

done_testing();
