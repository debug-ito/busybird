use strict;
use warnings;
use Test::More;
use BusyBird::Test::StatusStorage qw(:storage);
use Test::Exception;
use File::Temp;

BEGIN {
    use_ok('BusyBird::StatusStorage::SQLite');
}



sub create_storage {
    my ($filename) = @_;
    return BusyBird::StatusStorage::SQLite->new(path => $filename);
}

dies_ok { BusyBird::StatusStorage::SQLite->new(path => ':memory:') } "in-memory DB is not supported";

{
    my $tempfile = File::Temp->new;
    my $storage = create_storage($tempfile->filename);
    test_storage_common($storage);
    test_storage_ordered($storage);
    test_storage_missing_arguments($storage);
    test_storage_put_requires_ids($storage);
}

{
    my $tempfile = File::Temp->new;
    my $storage = BusyBird::StatusStorage::SQLite->new(
        path => $tempfile->filename, max_status_num => 5, hard_max_status_num => 10
    );
    test_storage_truncation($storage, {soft_max => 5, hard_max => 10});
}

done_testing();


