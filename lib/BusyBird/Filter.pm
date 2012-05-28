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
    $self->_setParam($param_ref, 'delay', 0);
    $self->{delay} = 0 if $self->{delay} < 0;
    $self->{coderefs} = [];
    $self->{jobqueue} = [];
    $self->{parallel_current} = 0;
}

sub filterElement {
    my ($self) = @_;
    return sub { $self->execute(@_) };
}

sub _addFilterElements {
    my ($self, $elems_ref, $add_method) = @_;
    foreach my $filter_elem (@$elems_ref) {
        next if !defined($filter_elem);
        die "A filter element must be either coderef or object." if !ref($filter_elem);
        if(ref($filter_elem) eq 'CODE') {
            $add_method->($self->{coderefs}, $filter_elem);
        }else {
            $add_method->($self->{coderefs}, $filter_elem->filterElement());
        }
    }
}

sub push {
    my ($self, @elems) = @_;
    $self->_addFilterElements(
        \@elems, sub {
            my ($a, $elem) = @_;
            CORE::push(@$a, $elem);
        }
    );
}

sub unshift {
    my ($self, @elems) = @_;
    $self->_addFilterElements(
        \@elems, sub {
            my ($a, $elem) = @_;
            CORE::unshift(@$a, $elem);
        }
    );
}

sub execute {
    my ($self, $target, $callback) = @_;
    if(@{$self->{coderefs}} == 0) {
        $callback->($target) if defined($callback);
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
    $self->{parallel_current}++;
    $single_callback = sub {
        my ($filtered_target) = @_;
        $index++;
        my $next_move;
        if($index >= @{$self->{coderefs}}) {
            $next_move = sub {
                $callback->($filtered_target) if defined($callback);
                $self->{parallel_current}--;
                if(my $next_job = CORE::shift(@{$self->{jobqueue}})) {
                    $self->_forceExecute(@$next_job);
                }
            };
        }else {
            $next_move = sub {
                $self->{coderefs}->[$index]->($filtered_target, $single_callback);
            };
        }
        my $tw; $tw = AnyEvent->timer(
            after => $self->{delay},
            cb => sub {
                undef $tw;
                $next_move->();
            },
        );
    };
    $self->{coderefs}->[$index]->($target, $single_callback);
}

1;



