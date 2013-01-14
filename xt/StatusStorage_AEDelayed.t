use strict;
use warnings;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use Test::More;
use Test::BusyBird::StatusStorage qw(:all);
use App::BusyBird::StatusStorage::Memory;
use App::BusyBird::StatusStorage::AEDelayed;
use AnyEvent;

my $cv;

sub loop {
    $cv = AnyEvent->condvar;
    $cv->recv;
}

sub unloop {
    $cv->send;
}

sub storage {
    my (%backend_args) = @_;
    return App::BusyBird::StatusStorage::AEDelayed->new(
        backend => App::BusyBird::StatusStorage::Memory->new(%backend_args)
    );
}

test_storage_common(storage(), \&loop, \&unloop);
test_storage_ordered(storage(), \&loop, \&unloop);
test_storage_truncation(storage(max_status_num => 2), 2, \&loop, \&unloop);

done_testing();
