use strict;
use warnings;
use lib "t";
use Test::More;
use Test::Builder;
use Test::Fatal qw(exception);
use Test::MockObject;
## use BusyBird::Test::StatusStorage qw(:status test_cases_for_ack);
## use testlib::Timeline_Util qw(sync status test_sets test_content *LOOP *UNLOOP);
use Test::Memory::Cycle;
## use BusyBird::DateTime::Format;
## use BusyBird::Log;
use DateTime;
use DateTime::Duration;
use Storable qw(dclone);
use utf8;

## use BusyBird::Timeline;
use BusyBird::StatusStorage::SQLite;
## use BusyBird::Watcher;
## use testlib::StatusStorage::AEDelayed;
use AnyEvent;

$Devel::Trace::TRACE = 0;

## ok(eval('use testlib::StatusStorage::AEDelayed; 1'), "AEDelayed OK");

{
    local $Devel::Trace::TRACE = 1;
    ##my $cv = AnyEvent->condvar;
    my $w; $w = AnyEvent->timer(after => 1, cb => sub {
        ##$cv->send;
        undef $w;
    });
    ##$cv->recv;
    pass("done");
}


done_testing;
