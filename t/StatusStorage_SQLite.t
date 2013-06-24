use strict;
use warnings;
use Test::More;
use BusyBird::Test::StatusStorage qw(:storage :status);
use Test::Exception;
use File::Temp;
use Test::MockObject::Extends;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use BusyBird::Test::Timeline_Util qw(sync status);

BEGIN {
    use_ok('BusyBird::StatusStorage::SQLite');
}



sub create_storage {
    my ($filename) = @_;
    return BusyBird::StatusStorage::SQLite->new(path => $filename);
}

dies_ok { BusyBird::StatusStorage::SQLite->new(path => ':memory:') } "in-memory DB is not supported";

if(0){
    my $tempfile = File::Temp->new;
    my $storage = create_storage($tempfile->filename);
    test_storage_common($storage);
    test_storage_ordered($storage);
    test_storage_missing_arguments($storage);
    test_storage_put_requires_ids($storage);
}

if(0){
    my $tempfile = File::Temp->new;
    my $storage = BusyBird::StatusStorage::SQLite->new(
        path => $tempfile->filename, max_status_num => 5, hard_max_status_num => 10
    );
    test_storage_truncation($storage, {soft_max => 5, hard_max => 10});
}

{
    note('------ vacuum_on_delete tests.');
    my $tempfile = File::Temp->new;
    my @vacuum_log = ();
    my $create_spied_storage = sub {
        my $storage = BusyBird::StatusStorage::SQLite->new(
            path => $tempfile->filename, 
            max_status_num => 10, hard_max_status_num => 20, vacuum_on_delete => 5
        );
        can_ok($storage, "vacuum");
        my $vacuum_orig = $storage->can('vacuum');
        Test::MockObject::Extends->new($storage);
        $storage->mock(vacuum => sub {
            push(@vacuum_log, [@_[1..$#_]]);
            goto $vacuum_orig;
        });
        return $storage;
    };
    my $storage = $create_spied_storage->();
    
    my %base = (timeline => "_test_tl_vacuum");
    my ($error, $ret_num);

    note("--- vacuum on delete (single)");
    ($error, $ret_num) = sync(
        $storage, 'put_statuses', %base,
        mode => 'insert', statuses => [map {status($_)} 1..10]
    );
    is($error, undef, "put succeeds");
    is($ret_num, 10, "10 inserted");
    ($error, $ret_num) = sync(
        $storage, 'delete_statuses', %base, ids => [7..10]
    );
    is($error, undef, "delete succeeds");
    is($ret_num, 4, '4 deleted');
    
    is(scalar(@vacuum_log), 0, 'vacuum should be called yet. Only 4 statuses are deleted.');

    ($error, $ret_num) = sync(
        $storage, 'delete_statuses', %base, ids => 6
    );
    is($error, undef, 'delete succeeds');
    is($ret_num, 1, "1 deleted");
    is(scalar(@vacuum_log), 1, 'vacuum should be called once.');

    note("--- vacuum on delete (whole timeline)");
    @vacuum_log = ();
    ($error, $ret_num) = sync(
        $storage, 'delete_statuses', %base, ids => undef
    );
    is($error, undef, 'delete succeeds');
    is($ret_num, 5, '5 deleted');
    is(scalar(@vacuum_log), 1, 'vacuum should be called once.');

    note('--- vacuum on delete (multiple ids)');
    @vacuum_log = ();
    ($error, $ret_num) = sync(
        $storage, 'put_statuses', %base, mode => 'insert', statuses => [map {status($_)} 1..13]
    );
    is($error, undef, 'put succeeds');
    is($ret_num, 13, '13 inserted');
    is(scalar(@vacuum_log), 0, "vacuum should not be called yet");
    ($error, $ret_num) = sync(
        $storage, 'delete_statuses', %base, ids => [1..13]
    );
    is($error, undef, 'delete succeeds');
    is($ret_num, 13, '13 deleted');
    is(scalar(@vacuum_log), 1, 'vacuum should be called once (no matter how many statuses are deleted in one delete_statuses())');

    note('--- vacuum on delete (due to truncation)');
    @vacuum_log = ();
    ($error, $ret_num) = sync(
        $storage, 'put_statuses', %base, mode => 'insert', statuses => [map {status($_)} 1..20]
    );
    is($error, undef, 'put succeeds');
    is($ret_num, 20, '20 inserted');
    is(scalar(@vacuum_log), 0, 'vacuum should not be called yet');
    ($error, $ret_num) = sync(
        $storage, 'put_statuses', %base, mode => 'insert', statuses => status(21)
    );
    is($error, undef, 'put succeeds');
    is($ret_num, 1, '1 inserted');
    ($error, my $statuses) = sync(
        $storage, 'get_statuses', %base, count => 'all'
    );
    is($error, undef, 'get succeeds');
    test_status_id_list($statuses, [reverse 12..21], '10 statuses due to status truncation');
    is(scalar(@vacuum_log), 1, 'vacuum should be called due to status truncation.');

    note('--- vacuum count is persistent');
    @vacuum_log = ();
    ($error, $ret_num) = sync(
        $storage, 'put_statuses', %base, mode => 'insert', statuses => [map {status($_)} 1..5]
    );
    is($error, undef, "put succeeds");
    is($ret_num, 5, '5 inserted');
    ($error, $ret_num) = sync(
        $storage, 'delete_statuses', %base, ids => [1..4]
    );
    is($error, undef, 'delete succeeds');
    is($ret_num, 4, '4 deleted');
    is(scalar(@vacuum_log), 0, 'vacuum should not be called yet');
    undef $storage;
    $storage = $create_spied_storage->();
    ($error, $ret_num) = sync(
        $storage, 'delete_statuses', %base, ids => 1,
    );
    is($error, undef, 'delete succeeds');
    is($ret_num, 1, '1 deleted');
    is(scalar(@vacuum_log), 1, 'vacuum should be called even though storage object is re-created.');

    {
        note('--- vacuum count is shared by all timelines.');
        @vacuum_log = ();
        my %base2 = (timeline => '_another_timeline_for_vacuum');
        sync($storage, 'put_statuses', %base, mode => 'insert', statuses => [map {status($_)} 1..4]);
        ($error, $ret_num) = sync($storage, 'delete_statuses', %base, ids => undef);
        is($error, undef, 'delete succeeds');
        is($ret_num, 4, '4 deleted');
        is(scalar(@vacuum_log), 0, 'vacuum should not be called yet');
        
        sync($storage, 'put_statuses', %base2, mode => 'insert', statuses => [map {status($_)} 1..10]);
        ($error, $ret_num) = sync($storage, 'delete_statuses', %base2, ids => 1);
        is($error, undef, 'delete succeeds');
        is($ret_num, 1, '1 deleted');
        is(scalar(@vacuum_log), 1, 'vacuum should be called because vacuum count is shared by all timelines.');
    }
}

{
    local $TODO = "reminder";
    fail('TODO: column manipulation to level, {utc,timezone}_{acked,created}_at and get_statuses()');
    fail('TODO: column manipulation to level and get_unacked_counts()');
    fail('TODO: put_statuses() with non-UTC timestamps');
}

done_testing();


