use strict;
use warnings;
use Test::More;
## use lib "t";
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
