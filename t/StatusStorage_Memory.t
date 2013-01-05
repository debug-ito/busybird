use strict;
use warnings;
use Test::More;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use Test::App::BusyBird::StatusStorage;

BEGIN {
    use_ok('App::BusyBird::StatusStorage::Memory');
}

my $storage = new_ok('App::BusyBird::StatusStorage::Memory');

test_status_storage($storage);

TODO: {
    our $TODO = "test and implementaion must be done";
    fail("save() and load() method");
    fail('load() on init, save() on DESTROY');
    fail('ordered status test');
}


done_testing();

