#!/usr/bin/perl -w

use strict;
use warnings;

use Getopt::Long;
use Scalar::Util qw(refaddr);
use Encode;
use FindBin;

sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }
sub POE::Kernel::ASSERT_DEFAULT    () { 1 }
use POE;



use Data::Dumper;

use Net::Twitter;

use BusyBird::Input;
use BusyBird::Input::Twitter::HomeTimeline;
use BusyBird::Input::Twitter::List;
use BusyBird::Input::Twitter::PublicTimeline;
use BusyBird::Input::Test;

use BusyBird::Filter;

use BusyBird::Output;
use BusyBird::Timer;
use BusyBird::HTTPD;
use BusyBird::Worker::Twitter;
use BusyBird::Status;

require 'config.test.pl';

my $OPT_THRESHOLD_OFFSET = 0;
GetOptions(
    't=s' => \$OPT_THRESHOLD_OFFSET,
);

sub main {
    ## ** TODO: support more sophisticated format of threshold offset (other than just seconds).
    BusyBird::Input->setThresholdOffset(int($OPT_THRESHOLD_OFFSET));
    my @outputs = &configBusyBird();

    BusyBird::HTTPD->init($FindBin::Bin . "/resources/httpd");
    BusyBird::HTTPD->registerOutputs(@outputs);
    BusyBird::HTTPD->start();
    POE::Kernel->run();
}

&main();

