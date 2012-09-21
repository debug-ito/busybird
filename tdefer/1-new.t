use warnings;
use strict;
use Test::More;
use Test::Exception;

use BusyBird::Defer;


plan tests => 1;


my ($d);


# new

$d = BusyBird::Defer->new();
ok $d,  'new Defer object created';


