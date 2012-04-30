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
    $self->_setParam(\%params, 'after', 1);
    my $tw; $tw = AnyEvent->timer(
        after => $self->{after},
        cb => sub {
            undef $tw;
            $self->_fire();
            $self->start();
        }
    );
    return $self;
}

sub start {
    my ($self) = @_;
    my $watcher;
    $watcher = AnyEvent->timer(
        after => $self->{interval},
        cb => sub {
            undef $watcher;
            $self->_fire();
            $self->start();
        }
    );
}

sub _fire {
    my ($self) = @_;
    foreach my $callback (@{$self->{callbacks}}) {
        $callback->();
    }
}

sub addOnFire {
    my ($self, @callbacks) = @_;
    push(@{$self->{callbacks}}, @callbacks);
}

1;

