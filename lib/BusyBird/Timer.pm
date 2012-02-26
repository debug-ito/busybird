package BusyBird::Timer;
use base ("BusyBird::Object");

use strict;
use warnings;

use POE;

use BusyBird::CallStack;

my $TIMER_INTERVAL_MIN = 60;

sub new {
    my ($class, %params) = @_;
    my $self = bless {
        input_streams => [],
        filters => [],
        output_streams => [],
        session => undef,
    }, $class;
    $self->_setParam(\%params, 'interval', undef, 1);
    $self->_setParam(\%params, 'aliased', undef);
    $self->_setParam(\%params, 'start_delay', 0);
    
    POE::Session->create(
        object_states => [
            $self => BusyBird::Object->objectStates(qw(_start timer_fire set_delay
                                                       on_get_from_input on_get_statuses_complete
                                                       on_filter_execute on_filters_complete)),
        ],
        inline_states => {
            _stop => sub {
                printf STDERR ("Timer session %d stopped.\n", $_[SESSION]->ID);
            },
        },
    );
    return $self;
}

sub _getNextDelay {
    my ($self) = @_;
    return $self->{interval};
}

sub setInterval {
    my ($self, $new_interval) = @_;
    $self->{interval} = $new_interval;
}

sub addInput {
    my ($self, @inputs) = @_;
    push(@{$self->{input_streams}}, @inputs);
}

sub addOutput {
    my ($self, @outputs) = @_;
    push(@{$self->{output_streams}}, @outputs);
}

sub startTimer {
    my ($self) = @_;
    POE::Kernel->post($self->{session}, "timer_fire");
}

sub _sessionStart {
    my ($self, $kernel, $session) = @_[OBJECT, KERNEL, SESSION];
    $self->{session} = $session->ID;
    if($self->{aliased}) {
        $kernel->alias_set($self->{session});
    }
    if($self->{start_delay} >= 0) {
        $kernel->delay("timer_fire", $self->{start_delay});
    }
}

sub _sessionSetDelay {
    my ($self, $kernel, $state) = @_[OBJECT, KERNEL, STATE];
    my $delay = $self->_getNextDelay();
    printf STDERR ("INFO: Following inputs will be checked in %.2f seconds.\n", $delay);
    foreach my $input (@{$self->{input_streams}}) {
        printf STDERR ("INFO:   %s\n", $input->getName());
    }
    $kernel->delay('timer_fire', $delay);
}

sub _sessionTimerFire {
    my ($self, $kernel, $session) = @_[OBJECT, KERNEL, SESSION];
    printf STDERR ("INFO: fire on input");
    foreach my $input (@{$self->{input_streams}}) {
        printf STDERR (" %s", $input->getName());
    }
    print STDERR "\n";

    ## @{$heap->{new_statuses}} = ();
    $self->_getNewStatuses(undef, $session->ID, 'on_get_statuses_complete');
}

sub _getNewStatuses {
    my ($self, $callstack, $ret_session, $ret_event) = @_;
    $callstack = BusyBird::CallStack->newStack($callstack, $ret_session, $ret_event, new_streams => []);
    foreach my $input (@{$self->{input_streams}}) {
        $input->getNewStatuses($callstack->clone(), $self->{session}, 'on_get_from_input');
    }
}

sub _executeFilters {
    my ($self, $callstack, $ret_session, $ret_event, $new_statuses_ref) = @_;
    my $filter_index = 0;
    $callstack = BusyBird::CallStack->newStack($callstack, $ret_session, $ret_event,
                                               filter_index => $filter_index);
    if(!@{$self->{filters}}) {
        print STDERR ("ERROR: There is no filters in this session!!!\n");
        ## return $kernel->yield('on_filters_complete', undef, \@new_statuses); ## for test
        $callstack->pop($new_statuses_ref);
        return;
    }
    $self->{filters}->[$filter_index]->execute($callstack, $self->{session}, 'on_filter_execute', $new_statuses_ref);
}

sub _sessionOnFilterExecute {
    my ($self, $kernel, $state, $session, $callstack, $statuses) = @_[OBJECT, KERNEL, STATE, SESSION, ARG0 .. ARG1];
    print STDERR ("main session(state => $state)\n");
    my $filter_index = $callstack->get('filter_index');
    $filter_index++;
    if($filter_index < int(@{$self->{filters}})) {
        $callstack->set('filter_index', $filter_index);
        $self->{filters}->[$filter_index]->execute($callstack, $session->ID, 'on_filter_execute', $statuses);
    }else {
        $callstack->pop($statuses);
    }
}

sub _sessionOnGetFromInput {
    my ($self, $kernel, $state, $session, $callstack, $ret_array) = @_[OBJECT, KERNEL, STATE, SESSION, ARG0 .. ARG1];
    print STDERR ("main session(state => $state)\n");
    my $new_streams = $callstack->get('new_streams');
    push(@$new_streams, $ret_array);
    printf STDERR ("main session: status input from a stream (now %d/%d streams).\n",
                   int(@$new_streams), int(@{$self->{input_streams}}));
    if(int(@$new_streams) != int(@{$self->{input_streams}})) {
        return;
    }
    my @new_statuses = ();
    foreach my $single_stream (@$new_streams) {
        push(@new_statuses, @$single_stream);
    }
    printf STDERR ("main session: %d statuses received.\n", int(@new_statuses));
    $callstack->pop(\@new_statuses);
}

sub _sessionOnGetStatusesComplete {
    my ($self, $kernel, $session, $callstack, $new_statuses) = @_[OBJECT, KERNEL, SESSION, ARG0 .. ARG1];
    if (defined($new_statuses) && @$new_statuses) {
        $self->_executeFilters($callstack, $session->ID, 'on_filters_complete', $new_statuses);
    }else {
        return $kernel->yield('set_delay');
    }
}

sub _sessionOnFiltersComplete {
    my ($self, $kernel, $session, $state, $callstack, $new_statuses) = @_[OBJECT, KERNEL, SESSION, STATE, ARG0 .. ARG1];
    print STDERR ("main session(state => $state)\n");
    ## for test: every status is given to every output.
    foreach my $output_stream (@{$self->{output_streams}}) {
        $output_stream->pushStatuses($new_statuses);
        $output_stream->onCompletePushingStatuses();
    }
    return $kernel->yield('set_delay');
}

sub _sessionChangeInterval {
    ## STUB?
    my ($self, $kernel, $heap, $interval) = @_[OBJECT, KERNEL, HEAP, ARG0];
    my $new_interval = ($interval < $TIMER_INTERVAL_MIN ? $TIMER_INTERVAL_MIN : $interval);
    $self->setInterval($new_interval);
    return $kernel->yield('set_delay');
}

1;
