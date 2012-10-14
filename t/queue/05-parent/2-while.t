use warnings;
use strict;
use Test::More;
use Test::Exception;

use BusyBird::Defer::Queue;


plan tests => 2;


my ($d);
my (@result);


# while
# - require CODE in first param
# - receive $d in first param with correct $d->iter()
# end_while

$d = BusyBird::Defer::Queue->new();
throws_ok { $d->while() } qr/require CODE/;

$d = BusyBird::Defer::Queue->new();
$d->while(sub{ my $i = $_[0]->iter(); push @result, $i; $i < 3 });
$d->do(sub{
    my ($d) = @_;
    push @result, $d->iter()*10;
    $d->done();
});
$d->end_while();
@result = (); $d->run();
is_deeply \@result, [1,10,2,20,3], 'receive $d in first param with correct $d->iter()';


