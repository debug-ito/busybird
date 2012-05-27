#!/usr/bin/perl -w

use strict;
use warnings;
use lib 't/lib';
use Test::More;

BEGIN {
    foreach my $bb_package (
        qw(
              Connector Filter HTTPD HTTPD::PathMatcher
              Input Input::Twitter Input::Twitter::PublicTimeline
              Input::Twitter::HomeTimeline Input::Twitter::List
              Input::Twitter::Search
              Input::Test
              Log Object Output Status Timer
              Worker::Exec Worker::Object Worker::Twitter
              ComponentManager
      )
    ) {
        use_ok('BusyBird::' . $bb_package);
    }
}

done_testing();




