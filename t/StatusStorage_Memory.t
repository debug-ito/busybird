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
    my $storage = new_ok('App::BusyBird::StatusStorage::Memory', [logger => undef]);
    test_storage_common($storage);
    test_storage_ordered($storage);
    ok($storage->save(), "save() without filepath option returns true");
    ok($storage->load(), "load() without filepath option returns true");
}

{
    my $storage = new_ok('App::BusyBird::StatusStorage::Memory', [max_status_num => 5, logger => undef]);
    test_storage_truncation($storage, 5);
}


done_testing();

