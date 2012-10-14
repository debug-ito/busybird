use warnings;
use strict;
use Test::More;
use Test::Exception;

use BusyBird::Defer::Queue;


plan tests => 1;


my ($d);


# new

$d = BusyBird::Defer::Queue->new();
ok $d,  'new Defer object created';


