#!/usr/bin/perl -w

use strict;
use warnings;

use Getopt::Long;
use FindBin;
use AnyEvent;

use BusyBird::Input;
use BusyBird::Output;
use BusyBird::Timer;

my $OPT_THRESHOLD_OFFSET = 0;
my $OPT_CONFIGFILE = 'config.test.pl';
GetOptions(
    't=s' => \$OPT_THRESHOLD_OFFSET,
    'c=s' => \$OPT_CONFIGFILE,
);


do "$OPT_CONFIGFILE";
if($@) {
    print STDERR ("Load config.test.pl error: $@\n");
    exit 1;
}


sub main {
    ## ** TODO: support more sophisticated format of threshold offset (other than just seconds).
    BusyBird::Input->setThresholdOffset(int($OPT_THRESHOLD_OFFSET));
    &configBusyBird($FindBin::Bin);
    AnyEvent->condvar->recv();
}

&main();

