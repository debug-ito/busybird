package BusyBird::CallStack;

use strict;
use warnings;
use POE;
use BusyBird::Log ('bblog');

sub newStack {
    my ($class, $existing_obj, $recv_session, $recv_event, %init_heap) = @_;
    if(defined($existing_obj)) {
        return $existing_obj->_push($recv_session, $recv_event, %init_heap);
    }else {
        return $class->new()->_push($recv_session, $recv_event, %init_heap);
    }
}

sub new {
    my ($class) = @_;
    my $self = bless {
        stack => [],
    }, $class;
    return $self;
}

sub clone {
    my ($self) = @_;
    my $cloned_stack = ref($self)->new();
    foreach my $stack_frame (@{$self->{stack}}) {
        $cloned_stack->_push($stack_frame->{recv_session},
                             $stack_frame->{recv_event},
                             %{$stack_frame->{heap}});
    }
    return $cloned_stack;
}

sub _push {
    my ($self, $recv_session, $recv_event, %init_heap) = @_;
    if(!defined($recv_session) or !defined($recv_event)) {
        return $self;
    }
    ## if(!defined(%init_heap)) {
    ##     %init_heap = ();
    ## }
    POE::Kernel->refcount_increment($recv_session, 'bb_callstack');
    CORE::push(@{$self->{stack}},
         {recv_session => $recv_session,
          recv_event   => $recv_event,
          heap         => \%init_heap,
      });
    return $self;
}

sub frameNum {
    my ($self) = @_;
    return int(@{$self->{stack}});
}

sub pop {
    my ($self, @return_values) = @_;
    if(!@{$self->{stack}}) {
        &bblog("CallStack: no stack entry to pop");
        die "CallStack: no stack entry to pop.";
    }
    my $entry = CORE::pop(@{$self->{stack}});
    POE::Kernel->post($entry->{recv_session}, $entry->{recv_event}, $self, @return_values);
    POE::Kernel->refcount_decrement($entry->{recv_session}, 'bb_callstack');
    return $self;
}

sub DESTROY {
    my ($self) = @_;
    while(my $entry = CORE::pop(@{$self->{stack}})) {
        POE::Kernel->refcount_decrement($entry->{recv_session}, 'bb_callstack');
    }
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

sub toString {
    my ($self, $with_heap) = @_;
    my $ret = "";
    for(my $i = 0 ; $i < int(@{$self->{stack}}) ; $i++) {
        my $entry = $self->{stack}->[$i];
        $ret .= sprintf("Stack %d: return to (%s, %s)\n",
                        $i, $entry->{recv_session}, $entry->{recv_event});
        if($with_heap) {
            while(my ($key, $val) = each(%{$entry->{heap}})) {
                $ret .= "  $key => $val\n";
            }
        }
    }
    return $ret;
}

1;


