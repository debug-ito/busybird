use strict;
use warnings;
use Test::More;
use BusyBird::Main;

{
    my $main = BusyBird::Main->new();
    my $tl = $main->timeline('dummy');
    my $storage = $main->get_config('default_status_storage');
    isa_ok($storage, 'BusyBird::StatusStorage::Memory', 'default default_status_storage is a BB::SS::Memory');
}


done_testing();


