package BusyBird::Timer;
use base ('BusyBird::Object', 'BusyBird::Connector');
use strict;
use warnings;

use AnyEvent;
use BusyBird::Filter;

sub new {
    my ($class, %params) = @_;
    my $self = bless {
        interval => undef,
        executer => undef,
    }, $class;
    $self->_setParam(\%params, 'interval', 120);
    $self->_setParam(\%params, 'after', 1);
    $self->_setParam(\%params, 'callback_interval', 0);
    $self->{executer} = BusyBird::Filter->new(delay => $self->{callback_interval});
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
    $self->{executer}->execute();
}

sub addOnFire {
    my ($self, @callbacks) = @_;
    foreach my $callback (@callbacks) {
        $self->{executer}->push( sub { $callback->(); $_[1]->($_[0]); } );
    }
}

sub c{
    my ($self, $to) = @_;
    return $self->SUPER::c(
        $to,
        'BusyBird::Input' => sub {
            $self->addOnFire( sub { $to->getStatuses() } );
        },
    );
}

1;

