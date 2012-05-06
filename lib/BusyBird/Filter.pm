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

sub pushFilters {
    my ($self, @filters) = @_;
    foreach my $filter (@filters) {
        $self->push(sub { $filter->execute(@_) });
    }
}

sub unshiftFilters {
    my ($self, @filters) = @_;
    foreach my $filter (@filters) {
        $self->unshift(sub { $filter->execute(@_) });
    }
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
    my ($self, $target, $callback) = @_;
    if(@{$self->{coderefs}} == 0) {
        $callback->($target);
        return;
    }
    my $index = 0;
    my $single_callback;
    $single_callback = sub {
        my ($filtered_target) = @_;
        $index++;
        if($index >= @{$self->{coderefs}}) {
            $callback->($filtered_target);
        }else {
            $self->{coderefs}->[$index]->($filtered_target, $single_callback);
        }
    };
    $self->{coderefs}->[$index]->($target, $single_callback);
}

1;



