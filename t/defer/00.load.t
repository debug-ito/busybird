use warnings;
use strict;
use Test::More tests => 1;

BEGIN { use_ok( 'BusyBird::Defer' ) or BAIL_OUT('unable to load module') }

diag( "Testing BusyBird::Defer $Async::Defer::VERSION, Perl $], $^X" );
