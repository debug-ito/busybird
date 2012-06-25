package BusyBird::Timer;
use base ('BusyBird::Connector');
use strict;
use warnings;

use AnyEvent;
use BusyBird::Filter;
use BusyBird::Util ('setParam');

sub new {
    my ($class, %params) = @_;
    my $self = bless {
        interval => undef,
        executer => undef,
        timer => undef,
    }, $class;
    $self->setParam(\%params, 'interval', 120);
    $self->setParam(\%params, 'after', 1);
    $self->setParam(\%params, 'callback_interval', 0);
    $self->{executer} = BusyBird::Filter->new(delay => $self->{callback_interval});
    $self->start();
    return $self;
}

sub start {
    my ($self, $after) = @_;
    $after = $self->{after} if !defined($after);
    $self->{timer} = AnyEvent->timer(
        after => $after,
        cb => sub {
            delete $self->{timer};
            $self->_fire();
            $self->start($self->{interval});
        }
    );
}

sub stop {
    my ($self) = @_;
    delete $self->{timer};
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

