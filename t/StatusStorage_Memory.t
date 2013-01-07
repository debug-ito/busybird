use strict;
use warnings;
use Test::More;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use Test::App::BusyBird::StatusStorage qw(:storage :status);

BEGIN {
    use_ok('App::BusyBird::StatusStorage::Memory');
}

{
    my $storage = new_ok('App::BusyBird::StatusStorage::Memory');
    test_storage_common($storage);
    test_storage_ordered($storage);
}

{
    my $storage = new_ok('App::BusyBird::StatusStorage::Memory', [max_status_num => 5]);
    test_storage_truncation($storage, 5);
}

TODO: {
    our $TODO = "test and implementaion must be done";
    fail("save() and load() method");
    fail('load() on init, save() on DESTROY');
}


done_testing();

