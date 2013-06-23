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
    test_storage_common(create_storage($tempfile->filename));
}

## test_storage_ordered;
## test_storage_truncation;
## test_storage_missing_arguments;
## test_storage_put_requires_ids;

{
    local $TODO = "reminder";
    fail('TODO: storage truncation is per-timeline (general test)');
    fail('TODO: insert statuses with the same ID (general test, unordered)');
    fail('TODO: insert statuses with the same timestamps (general test, ordered)');
    fail('TODO: ack max_id and ids: duplicate selection (some IDs are selected both by max_id and ids)');
}

done_testing();


