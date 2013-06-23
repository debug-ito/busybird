use strict;
use warnings;
use Test::More;
use BusyBird::Test::StatusStorage qw(:storage);

BEGIN {
    use_ok('BusyBird::StatusStorage::SQLite');
}

sub create_storage {
    return BusyBird::StatusStorage::SQLite->new(path => ':memory:');
}

$Carp::Verbose = 1;

{
    test_storage_common(create_storage());
}

## test_storage_ordered;
## test_storage_truncation;
## test_storage_missing_arguments;
## test_storage_put_requires_ids;

{
    local $TODO = "reminder";
    fail('TODO: do the whole tests both for :memory: and temp file.');
    fail('TODO: storage truncation is per-timeline (general test)');
    fail('TODO: insert statuses with the same ID (general test, unordered)');
    fail('TODO: insert statuses with the same timestamps (general test, ordered)');
    fail('TODO: ack max_id and ids: duplicate selection (some IDs are selected both by max_id and ids)');
}

done_testing();


