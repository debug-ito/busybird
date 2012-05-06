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
    $self->_setParam($param_ref, 'parallel_limit', 1);
    $self->{coderefs} = [];
    $self->{jobqueue} = [];
    $self->{parallel_current} = 0;
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
    if($self->{parallel_limit} > 0 && $self->{parallel_current} >= $self->{parallel_limit}) {
        CORE::push(@{$self->{jobqueue}}, [$target, $callback]);
        return;
    }
    $self->_forceExecute($target, $callback);
}

sub _forceExecute {
    my ($self, $target, $callback) = @_;
    my $index = 0;
    my $single_callback;
    $self->{parallel_count}++;
    $single_callback = sub {
        my ($filtered_target) = @_;
        $index++;
        if($index >= @{$self->{coderefs}}) {
            $callback->($filtered_target);
            $self->{parallel_count}--;
            if(my $next_job = CORE::pop(@{$self->{jobqueue}})) {
                $self->_forceExecute(@$next_job);
            }
        }else {
            $self->{coderefs}->[$index]->($filtered_target, $single_callback);
        }
    };
    $self->{coderefs}->[$index]->($target, $single_callback);
}

1;



