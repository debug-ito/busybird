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
use DBI;

BEGIN {
    use_ok('BusyBird::StatusStorage::SQLite');
}

sub connect_db {
    my ($filename) = @_;
    return DBI->connect("dbi:SQLite:dbname=$filename", "", "", {
        PrintError => 0, RaiseError => 1, AutoCommit => 1
    });
}

dies_ok { BusyBird::StatusStorage::SQLite->new(path => ':memory:') } "in-memory DB is not supported";

if(0){
    my $tempfile = File::Temp->new;
    my $storage = BusyBird::StatusStorage::SQLite->new(path => $tempfile->filename);
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

if(0){
    note('------ vacuum_on_delete tests.');
    my $tempfile = File::Temp->new;
    my @vacuum_log = ();
    my $create_spied_storage = sub {
        my $storage = BusyBird::StatusStorage::SQLite->new(
            path => $tempfile->filename, 
            max_status_num => 10, hard_max_status_num => 20, vacuum_on_delete => 5
        );
        can_ok($storage, "vacuum");
        my $vacuum_orig = $storage->can('_do_vacuum');
        Test::MockObject::Extends->new($storage);
        $storage->mock(_do_vacuum => sub {
            push(@vacuum_log, [@_[1..$#_]]);
            goto $vacuum_orig;
        });
        return $storage;
    };
    my $storage = $create_spied_storage->();
    
    my %base = (timeline => "_test_tl_vacuum");
    my ($error, $ret_num);

    note('--- manual vacuum()');
    @vacuum_log = ();
    $storage->vacuum();
    is(scalar(@vacuum_log), 1, "vacuum called via public vacuum() method");

    note("--- vacuum on delete (single)");
    @vacuum_log = ();
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
    
    is(scalar(@vacuum_log), 0, 'vacuum should not be called yet. Only 4 statuses are deleted.');

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
    ($error, $ret_num) = sync($storage, "delete_statuses", %base, ids => undef);
    is($error, undef, "delete succeeds. timeline cleared.");
    is($ret_num, 10, "10 deleted");
    is(scalar(@vacuum_log), 2, "vacuum should be called once again by explicit call to delete_statuses.");

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
        $storage, 'delete_statuses', %base, ids => 5,
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
    note('--- manipulation to DB timestamp columns is reflected to obtained stutuses');
    my $tempfile = File::Temp->new;
    my $storage = BusyBird::StatusStorage::SQLite->new(path => $tempfile);
    my %base = (timeline => '_test_timestamp_cols');
    my ($error, $ret_num);
    ($error, $ret_num) = sync($storage, 'put_statuses', %base, mode => 'insert', statuses => status(1));
    is($error, undef, "put succeed");
    is($ret_num, 1, "1 inserted");

    my $dbh = connect_db($tempfile->filename);
    my $count = $dbh->do(<<SQL, undef, '2013-01-01T04:32:50', '-1000', '2012-12-31T22:41:05', '+0900', 1);
UPDATE statuses SET utc_acked_at = ?, timezone_acked_at = ?,
                    utc_created_at = ?, timezone_created_at = ?
              WHERE id = ?
SQL
    is($count, 1, '1 row updated');
    ($error, my $statuses) = sync($storage, 'get_statuses', %base, count => 'all');
    is($error, undef, "get succeeds");
    is(scalar(@$statuses), 1, "1 status obtained");
    is($statuses->[0]{busybird}{acked_at}, 'Mon Dec 31 18:32:50 -1000 2012', 'acked_at timestamp restored');
    is($statuses->[0]{created_at}, 'Tue Jan 01 07:41:05 +0900 2013', 'created_at timestamp restored');
}

{
    note('--- manipulation to DB level columns is reflected to obtained statuses');
    my $tempfile = File::Temp->new;
    my $storage = BusyBird::StatusStorage::SQLite->new(path => $tempfile);
    my %base = (timeline => '_test_level_cols');
    my ($error, $ret_num);
    ($error, $ret_num) = sync($storage, 'put_statuses', %base, mode => 'insert', statuses => status(1));
    is($error, undef, "put succeed");
    is($ret_num, 1, "1 inserted");
    ($error, my $unacked_counts) = sync($storage, 'get_unacked_counts', %base);
    is($error, undef, "get_unacked_counts succeed");
    is_deeply($unacked_counts, {total => 1, 0 => 1}, '1 status in level 0');

    my $dbh = connect_db($tempfile->filename);
    my $count = $dbh->do(<<SQL, undef, 5, 1);
UPDATE statuses SET level = ? WHERE id = ?
SQL
    ($error, $unacked_counts) = sync($storage, 'get_unacked_counts', %base);
    is($error, undef, "get_unacked_counts succeed");
    is_deeply($unacked_counts, {total => 1, 5 => 1}, '1 status in level 5');
    ($error, my $statuses) = sync($storage, 'get_statuses', %base, count => 'all');
    is($error, undef, "get succeed");
    is(scalar(@$statuses), 1, "1 status obtained");
    is($statuses->[0]{busybird}{level}, 5, "level is set to 5");
}

{
    local $TODO = "reminder";
    fail('TODO: enable all tests (remove if(0))');
    fail('TODO: put_statuses() with non-UTC timestamps');
}

done_testing();


