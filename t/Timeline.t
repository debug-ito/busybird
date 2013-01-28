use strict;
use warnings;
use Test::More;
use Test::Builder;
use Test::Exception;
use Test::BusyBird::StatusStorage qw(:status);
use App::BusyBird::DateTime::Format;
use DateTime;

BEGIN {
    use_ok('App::BusyBird::Timeline');
    use_ok('App::BusyBird::StatusStorage::Memory');
}

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
    my ($id) = @_;
    return {
        id => $id,
        created_at => App::BusyBird::DateTime::Format->format_datetime(
            DateTime->from_epoch(epoch => $id, time_zone => 'UTC')
        )
    };
}

sub test_content {
    my ($timeline, $args_ref, $exp, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ($statuses) = sync($timeline, 'get_statuses', %$args_ref);
    test_status_id_list($statuses, $exp, $msg);
}

my $CLASS = 'App::BusyBird::Timeline';

{
    note('-- checking names');
    my %s = (storage => create_storage(), logger => undef);
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
        logger => undef
    );
    my $timeline = new_ok($CLASS, [%newbase, name => 'test']);
    is($timeline->name(), 'test', 'name OK');
    test_content($timeline, {count => 'all'}, [], 'status is empty');
    my ($ret) = sync($timeline, 'add_statuses', statuses => [map {status($_)} (1..10)]);
    is($ret, 10, '10 added');
    test_content($timeline, {count => 'all', ack_state => 'unacked'},
                 [reverse 1..10], '10 unacked');
    test_content($timeline, {count => 'all', ack_state => 'acked'}, [], '0 acked');
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
    });
    ok($callbacked, 'add callbacked');
    test_content($timeline, {count => 'all', ack_state => 'unacked'}, [reverse 11..20], '10 unacked');
    test_content($timeline, {connt => 'all', ack_state => "acked"}, [reverse 1..10], '10 acked');
    test_content($timeline, {count => 10, ack_state => 'any', max_id => 15}, [reverse 6..15], 'get: count and max_id query');
    test_content($timeline, {count => 20, ack_state => 'acked', max_id => 12}, [], 'get: conflicting ack_state and max_id');
    test_content($timeline, {count => 10, ack_state => 'unacked', max_id => 12}, [reverse 11,12], 'get: only unacked');
    ($ret) = sync($timeline, 'ack_statuses', max_id => 15);
    is($ret, 5, '5 acked');
    test_content($timeline, {count => 'all', ack_state => 'unacked'}, [reverse 16..20], '5 unacked');
    ($ret) = sync($timeline, 'delete_statuses', ids => 18);
    is($ret, 1, '1 deleted');
    test_content($timeline, {count => 'all', ack_state => 'unacked'}, [reverse 16,17,19,20], '4 unacked');
    ($ret) = sync($timeline, 'delete_statuses', ids => [15,16,17,18]);
    is($ret, 3, '3 deleted');
    test_content($timeline, {count => 'all'}, [reverse 1..14, 19..20], '14 acked, 2 unacked');
    ($ret) = sync($timeline, 'put_statuses', mode => 'insert', statuses => [map {status($_)} 19..22]);
    is($ret, 2, '2 inserted');
    test_content($timeline, {count => 'all'}, [reverse 1..14, 19..22], '14 acked, 4 unacked');
    ($ret) = sync($timeline, 'put_statuses', mode => 'update', statuses => [map {status($_)} 13..17]);
    is($ret, 2, '2 updated');
    test_content($timeline, {count => 'all', ack_state => "unacked"}, [reverse 13,14,19..22], '6 unacked');
    test_content($timeline, {count => 'all', ack_state => "acked"}, [reverse 1..12], '12 unacked');
    ($ret) = sync($timeline, 'put_statuses', mode => 'upsert', statuses => [map {status($_)} 11..18]);
    is($ret, 8, '8 upserted');
    test_content($timeline, {count => 'all', ack_state => "unacked"}, [reverse 11..22], '12 unacked');
    test_content($timeline, {count => 'all', ack_state => "acked"}, [reverse 1..10], '10 unacked');
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
}



TODO: {
    local $TODO = "I will write these tests. I swear.";
    fail('todo: get_unacked_counts');
    fail('todo: timeline is properly destroyed. no cyclic reference between resource provider (see 2013/01/27)');
    fail('todo: concurrency control for asynchronous filters. The concurrency must be regulated.');
}

done_testing();
