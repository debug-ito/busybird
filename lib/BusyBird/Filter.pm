package BusyBird::Filter;
use base ("BusyBird::Object");

use strict;
use warnings;

use AnyEvent;

sub new {
    my ($class, %params) = @_;
    my $self = bless {}, $class;
    $self->_setParams(\%params);
    return $self;
}

sub _setParams {
    my ($self, $param_ref) = @_;
    $self->{coderefs} = [];
}

sub push {
    my ($self, @coderefs) = @_;
    CORE::push(@{$self->{coderefs}}, @coderefs);
}

sub unshift {
    my ($self, @coderefs) = @_;
    CORE::unshift(@{$self->{coderefs}}, @coderefs);
}

sub execute {
    my ($self, $statuses, $callback) = @_;
    if(@{$self->{coderefs}} == 0) {
        $callback->($statuses);
        return;
    }
    my $index = 0;
    my $single_callback;
    $single_callback = sub {
        my ($filtered_statuses) = @_;
        $index++;
        if($index >= @{$self->{coderefs}}) {
            $callback->($filtered_statuses);
        }else {
            $self->{coderefs}->[$index]->($filtered_statuses, $single_callback);
        }
    };
    $self->{coderefs}->[$index]->($statuses, $single_callback);
}

1;



