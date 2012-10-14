
use strict;
use warnings;
use Test::More;
use Test::Exception;

BEGIN {
    use_ok('BusyBird::Defer::Queue');
}


package Fake::NoDefer;
use strict;
use warnings;

sub new {
    my $class = shift;
    return bless {}, $class;
}

sub run {
    my ($self, $parent, @result) = @_;
    if(defined($parent)) {
        return $parent->done(@result);
    }
    return $self;
}


package Fake::Defer;
use base ('Fake::NoDefer');

sub clone {
    return ref(shift)->new();
}

sub done {
    1;
}

package main;

my $d = new_ok('BusyBird::Defer::Queue');
my $fake = Fake::Defer->new();
my @ret = ();

sub pusher {
    my ($val) = @_;
    return sub {
        my ($d) = @_;
        push(@ret, $val);
        $d->done;
    };
}

$d->do(pusher 1);

lives_ok {
    $d->do($fake);
} 'do() accepts Fake::Defer';

$d->do(pusher 2);

lives_ok {
    $d->do([$fake, $fake, $fake]);
} 'do([...]) accepts Fake::Defer';

$d->do(pusher 3);

lives_ok {
    $d->do({a => $fake, b => $fake, c => $fake});
} 'do({...}) accepts Fake::Defer';

$d->do(pusher 4);

my $invalid = Fake::NoDefer->new();

dies_ok {
    $d->do($invalid);
} 'do() rejects Fake::NoDefer';

dies_ok {
    $d->do([$invalid, $invalid, $invalid]);
} 'do([...]) rejects Fake::NoDefer';

dies_ok {
    $d->do({a => $invalid, b => $invalid, c => $invalid});
} 'do({...}) rejects Fake::NoDefer';

lives_ok {
    $d->run();
} 'run() runs Defer containing Fake::Defer correctly.';
is_deeply(\@ret, [1 .. 4], "ret OK");
@ret = ();

lives_ok {
    $d->run(Fake::Defer->new);
} 'run(FakeDefer->new) runs correctly, too.';
is_deeply(\@ret, [1..4], "ret OK");
@ret = ();

dies_ok {
    $d->run($invalid);
} 'run() rejects Fake::NoDefer';

done_testing();

