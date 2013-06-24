use strict;
use warnings;
use Test::More;
use BusyBird::Test::StatusStorage qw(:storage :status);

BEGIN {
    use_ok('BusyBird::StatusStorage::Memory');
}

{
    my $storage = new_ok('BusyBird::StatusStorage::Memory', [logger => undef]);
    test_storage_common($storage);
    test_storage_ordered($storage);
    test_storage_missing_arguments($storage);
    test_storage_put_requires_ids($storage);
}

{
    my $storage = new_ok('BusyBird::StatusStorage::Memory', [max_status_num => 5, logger => undef]);
    test_storage_truncation($storage, {soft_max => 5, hard_max => 5});
}


done_testing();

