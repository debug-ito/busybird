#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'BusyBird::Defer::Queue' ) || print "Bail out!\n";
}

diag( "Testing BusyBird::Defer::Queue $Async::Defer::Queue::VERSION, Perl $], $^X" );
