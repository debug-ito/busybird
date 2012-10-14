use warnings;
use strict;
use Test::More;
use Test::Exception;

use BusyBird::Defer::Queue;

## The test is imported from BusyBird::Defer and modified.


plan tests => 19;


my ($d, $p, $c);
my ($result, @result);


# clone
# - orig not used: orig and cloned are independent
# - orig was used: cloned have no parent
# - orig is running and in while(): cloned have clean 'not used' state

$d = BusyBird::Defer::Queue->new();
$d->{a} = 10;
$d->do(sub{
    my ($d) = @_;
    $d->{b} = 20;
    is $d->{a}, 10, 'The defers have {a} in run()';
    $d->done();
});
$d->do(sub {
    my ($d) = @_;
    is $d->{b}, 20, 'able to access {b} in run()';
    $d->done();
});
$c = $d->clone();
$d->run();
is $d->{a}, 10,     'orig have initial {a}';
is $c->{a}, 10,     'clone also have it';
## is $d->{b}, 20,     'orig also have {b}, created while run()';
is $d->{b}, undef,  'orig does not have {b} even after run(), because run() creates a different namespace.';
is $c->{b}, undef,  'clone does not have {b} before run()';
$c->run();
## is $c->{b}, 20,     'clone also have {b}, created while run()';
is $c->{b}, undef,     'clone does not have {b} either even after run()';
$c->do(sub{
    my ($d) = @_;
    $d->{c} = 30;
    $d->done();
});
$c->run();
$d->run();
is $d->{c}, undef,  'orig does not have {c} after second run()';
## is $c->{c}, 30,     'clone does have {c} after second run()';
is $c->{c}, undef,     'clone does not have {c} even after second run(). Namespace is different, I tell you.';

$p = BusyBird::Defer::Queue->new();
$d = BusyBird::Defer::Queue->new();
$c = undef;
$p->do($d);
$d->do(sub{
    my ($d) = @_;
    if (!defined $c) {
        $c = $d->clone();
        $result = undef; $c->run();
        is $result, undef,  'orig is running and have parent, but clone does not';
        $result = undef;
    }
    $d->done(10);
});
$p->do(sub{
    my ($d, $param) = @_;
    $result = $param;
    $d->done();
});
$result = undef; $p->run();
is $result, 10,     'orig run within parent';
$result = undef; $d->run();
is $result, undef,  'orig run independently';

@result = ();
$d = BusyBird::Defer::Queue->new();
$c = undef;
$d->while(sub{ $_[0]->iter() <= 4 });
$d->do(sub{
    my ($d) = @_;
    push @result, $d->iter();
    if ($d->iter() == 2 && !defined $c) {
        $c = $d->clone();
        $c->run();
    }
    $d->done();
});
$d->end_while();
$d->run();
is_deeply \@result, [1,2,1,2,3,4,3,4], 'orig was in while, clone was not';


