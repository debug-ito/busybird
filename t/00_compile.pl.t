#!/usr/bin/perl -w

use strict;
use warnings;
use lib 't/lib';
use Test::More;

BEGIN {
    foreach my $bb_package (
        qw(
              Connector Filter HTTPD HTTPD::PathMatcher
              Input InputDriver::Twitter InputDriver::Twitter::PublicTimeline
              InputDriver::Twitter::HomeTimeline InputDriver::Twitter::List
              InputDriver::Twitter::Search
              InputDriver::Test
              Log Util Output Status Timer
              Worker::Exec Worker::Object Worker::Twitter
              ComponentManager
      )
    ) {
        use_ok('BusyBird::' . $bb_package);
    }
}

done_testing();




