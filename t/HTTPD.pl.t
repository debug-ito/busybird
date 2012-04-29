#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('FindBin');
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('BusyBird::HTTPD');
}

ok(chdir($FindBin::Bin . '/../'), "change the current directory to the base");

my $cv = AnyEvent->condvar;
BusyBird::HTTPD->init();
BusyBird::HTTPD->start();
$cv->recv();

done_testing();

