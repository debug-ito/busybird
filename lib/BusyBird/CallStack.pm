package BusyBird::CallStack;

use strict;
use warnings;
use POE;

sub newStack {
    my ($class, $existing_obj, $recv_session, $recv_event, %init_heap) = @_;
    if(defined($existing_obj)) {
        return $existing_obj->push($recv_session, $recv_event, %init_heap);
    }else {
        return $class->new()->push($recv_session, $recv_event, %init_heap);
    }
}

sub new {
    my ($class) = @_;
    my $self = bless {
        stack => [],
    }, $class;
    return $self;
}

sub push {
    my ($self, $recv_session, $recv_event, %init_heap) = @_;
    if(!defined($recv_session) or !defined($recv_event)) {
        return $self;
    }
    ## if(!defined(%init_heap)) {
    ##     %init_heap = ();
    ## }
    CORE::push(@{$self->{stack}},
         {recv_session => $recv_session,
          recv_event   => $recv_event,
          heap         => \%init_heap,
      });
    return $self;
}

sub pop {
    my ($self, @return_values) = @_;
    if(!@{$self->{stack}}) {
        die "CallStack: no stack entry to pop.";
    }
    my $entry = pop(@{$self->{stack}});
    POE::Kernel->post($entry->{recv_session}, $entry->{recv_event}, $self, @return_values);
    return $self;
}

sub size {
    my ($self) = @_;
    return int(@{$self->{stack}});
}

sub _heap {
    my ($self, $index) = @_;
    if(!defined($index)) {
        $index = $self->size - 1;
    }
    $index = int($index) % $self->size;
    return $self->{stack}->[$index]->{heap};
}

sub get {
    my ($self, @keys) = @_;
    my @vals = ();
    my $heap = $self->_heap;
    foreach my $key (@keys) {
        CORE::push(@vals, $heap->{$key});
    }
    return wantarray ? @vals : $vals[0];
}

sub set {
    my ($self, %keyvals) = @_;
    my $heap = $self->_heap;
    while(my ($key, $val) = each(%keyvals)) {
        $heap->{$key} = $val;
    }
}

1;


