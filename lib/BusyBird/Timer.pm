package BusyBird::Timer;
use base ('BusyBird::Object');
use strict;
use warnings;

use AnyEvent;

sub new {
    my ($class, %params) = @_;
    my $self = bless {
        interval => undef,
        callbacks => [],
    }, $class;
    $self->_setParam(\%params, 'interval', 120);
    $self->start();
    return $self;
}

sub start {
    my ($self) = @_;
    my $watcher;
    $watcher = AnyEvent->timer(
        after => $self->{interval},
        cb => sub {
            undef $watcher;
            foreach my $callback (@{$self->{callbacks}}) {
                $callback->();
            }
            $self->start();
        }
    );
}

sub addOnFire {
    my ($self, @callbacks) = @_;
    push(@{$self->{callbacks}}, @callbacks);
}

1;

