package BusyBird::Worker;
use base 'BusyBird::Object';
use strict;
use warnings;
use POE qw(Wheel::Run Filter::Stream Filter::Line);
use BusyBird::CallStack;
use BusyBird::Log ('bblog');

=pod

=head1 NAME

BusyBird::Worker - Generic non-blocking wrapper for blocking routines


=head1 METHODS

=head2 WORKER_OBJ = new(PARAMS)

Create a BusyBird::Worker object.
PARAMS is a hash whose items are following.

=over

=item Program

=item StdinFilter

=item StdoutFilter

=item StderrFilter

=back


=cut


sub new {
    my ($class, %params) = @_;
    my $self = bless {
        children_by_wid => {},
        children_by_pid => {},
        session => undef,
    }, $class;
    $self->_setParam(\%params, 'Program', undef, 1);
    $self->_setParam(\%params, 'StdinFilter',  POE::Filter::Stream->new());
    $self->_setParam(\%params, 'StdoutFilter', POE::Filter::Stream->new());
    $self->_setParam(\%params, 'StderrFilter', POE::Filter::Line->new());
    $self->_initSession();
    ## if($self->_isDaemon) {
    ##     $self->_exec();
    ## }
    return $self;
}

sub startJob {
    my ($self, $callstack, $receiver_session_id, $receiver_event_name, $input_obj) = @_;
    POE::Kernel->post($self->{session}, "on_input",
                      BusyBird::CallStack->newStack($callstack, $receiver_session_id, $receiver_event_name, input_obj => $input_obj));
}

sub _initSession {
    my ($self) = @_;
    POE::Session->create(
        inline_states => {
            _stop => sub {},
        },
        object_states => [
            $self => {
                _start => '_sessionStart',
                ## on_exec => '_sessionExec',
                on_input => '_sessionInput',
                on_child_stdin  => '_sessionChildStdin',
                on_child_stdout => '_sessionChildStdout',
                on_child_stderr => '_sessionChildStderr',
                on_child_signal => '_sessionChildSignal',
            },
        ],
    );
}

sub _sessionStart {
    my ($self, $kernel, $session) = @_[OBJECT, KERNEL, SESSION];
    ## ** give alias to make the session immortal.
    $self->{session} = $session->ID;
    $kernel->alias_set($session->ID);
}

sub _sessionInput {
    my ($self, $callstack) = @_[OBJECT, ARG0];
    my $child = POE::Wheel::Run->new(
        Program => $self->{Program},
        StdinEvent   => 'on_child_stdin',
        StdoutEvent  => "on_child_stdout",
        StderrEvent  => "on_child_stderr",
        StdinFilter  => $self->{StdinFilter},
        StdoutFilter => $self->{StdoutFilter},
        StderrFilter => $self->{StderrFilter},
    );
    $_[KERNEL]->sig_child($child->PID, "on_child_signal");
    $callstack->set(wheel => $child,
                    output_objs => [],
                    exit_status => 0);
    $self->{children_by_wid}->{$child->ID} = $callstack;
    $self->{children_by_pid}->{$child->PID} = $callstack;
    ## $callstack->put();
    $child->put($callstack->get('input_obj'));
}

sub _sessionChildStdin {
    my ($self, $wheel_id) = @_[OBJECT, ARG0];
    $self->{children_by_wid}->{$wheel_id}->get('wheel')->shutdown_stdin();
}

sub _sessionChildStdout {
    my ($self, $output, $wheel_id) = @_[OBJECT, ARG0, ARG1];
    ## $self->{children_by_wid}->{$wheel_id}->pushOutput($output);
    push(@{$self->{children_by_wid}->{$wheel_id}->get('output_objs')}, $output);
}

sub _sessionChildStderr {
    my ($self, $output, $wheel_id) = @_[OBJECT, ARG0, ARG1];
    &bblog(sprintf(">> From WorkerChild WID=%d: %s", $wheel_id, $output));
}

sub _sessionChildSignal {
    my ($self, $pid, $exit_val) = @_[OBJECT, ARG1, ARG2];
    ## my $worker_child = $self->{children_by_pid}->{$pid};
    ## $worker_child->setExitStatus($exit_val);
    my $callstack = $self->{children_by_pid}->{$pid};
    $callstack->set(exit_status => $exit_val);
    ## $worker_child->report();
    ## delete $self->{children_by_wid}->{$worker_child->ID};
    delete $self->{children_by_wid}->{$callstack->get('wheel')->ID};
    delete $self->{children_by_pid}->{$pid};
    $callstack->pop($callstack->get(qw(output_objs input_obj exit_status)));
}

1;



