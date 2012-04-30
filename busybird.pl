#!/usr/bin/perl -w

use strict;
use warnings;

use Getopt::Long;
use FindBin;
use AnyEvent;

use BusyBird::Input;
use BusyBird::Output;
use BusyBird::Timer;

do "config.test.pl";

my $OPT_THRESHOLD_OFFSET = 0;
GetOptions(
    't=s' => \$OPT_THRESHOLD_OFFSET,
);

sub main {
    ## ** TODO: support more sophisticated format of threshold offset (other than just seconds).
    BusyBird::Input->setThresholdOffset(int($OPT_THRESHOLD_OFFSET));
    &configBusyBird($FindBin::Bin);
    AnyEvent->condvar->recv();
}

&main();

