package BusyBird::Worker;
use base 'BusyBird::Object';
use strict;
use warnings;

use POE;
use BusyBird::Worker::Child;

sub new {
    my ($class, %params) = @_;
    my $self = bless {
        children_by_wid => {},
        children_by_pid => {},
        session => undef,
    }, $class;
    $self->_setParam(\%params, 'Program', undef, 1);
    $self->_setParam(\%params, 'StdinFilter',  'POE::Filter::Stream');
    $self->_setParam(\%params, 'StdoutFilter', 'POE::Filter::Stream');
    $self->_setParam(\%params, 'StderrFilter', 'POE::Filter::Line');
    $self->_initSession();
    ## if($self->_isDaemon) {
    ##     $self->_exec();
    ## }
    return $self;
}

sub startJob {
    my ($self, $receiver_session_id, $receiver_event_name, $input_obj) = @_;
    POE::Kernel->post($self->{session}, "on_input",
                      BusyBird::Worker::Child->new($receiver_session_id, $receiver_event_name, $input_obj));
    ## $self->_push($receiver_session_id, $receiver_event_name, $input_obj);
    ## if($self->_isBusy) {
    ##     return;
    ## }
    ## if($self->_isDeamon) {
    ##     POE::Kernel->post($self->{session}, 'on_input');
    ## }else {
    ##     POE::Kernel->post($self->{session}, 'on_exec');
    ## }
}

## sub _push {
##     my ($self, $receiver_session_id, $receiver_event_name, $input_obj) = @_;
##     push(@{$self->{input_queue}},
##          {
##              receiver_session_id => $receiver_session_id,
##              receiver_event_name => $receiver_event_name,
##              input_obj           => $input_obj,
##          });
## }

## sub _isDaemon {
##     my ($self) = @_;
##     return $self->{is_daemon};
## }
## 
## sub _isBusy {
##     my ($self) = @_;
##     return $self->{is_busy};
## }
## 
## sub _setBusy {
##     my ($self, $busy_state) = @_;
##     $self->{is_busy} = $busy_state;
## }

## sub _exec {
##     my ($self) = @_;
##     POE::Kernel->post($self->{session}, 'on_exec');
## }

sub _initSession {
    my ($self) = @_;
    my $session = POE::Session->create{
        object_states => [
            $self => {
                ## on_exec => '_sessionExec',
                on_input => '_sessionInput',
                on_child_stdout => '_sessionChildStdout',
                on_child_stderr => '_sessionChildStderr',
                on_child_signal => '_sessionChildSignal',
            },
        ],
    };
    $self->{session} = $session->ID;
}

## sub _sessionExec {
##     my ($self) = @_[OBJECT];
##     my $child = POE::Wheel::Run->new(
##         Program => $self->{Program};
##         StdoutEvent  => "on_child_stdout",
##         StderrEvent  => "on_child_stderr",
##         StdinFilter  => $self->{StdinFilter},
##         StdoutFilter => $self->{StdoutFilter},
##         StderrFilter => $self->{StderrFilter},
##     );
##     $self->{child} = $child;
##     $_[KERNEL]->sig_child($child->PID, "on_child_signal");
##     ## if(!$self->_isDaemon) {
##     ##     @_[KERNEL]->post($self->{session}, 'on_input');
##     ## }
## }

sub _sessionInput {
    my ($self, $worker_child) = @_[OBJECT, ARG0];
    my $child = POE::Wheel::Run->new(
        Program => $self->{Program};
        StdoutEvent  => "on_child_stdout",
        StderrEvent  => "on_child_stderr",
        StdinFilter  => $self->{StdinFilter},
        StdoutFilter => $self->{StdoutFilter},
        StderrFilter => $self->{StderrFilter},
    );
    $_[KERNEL]->sig_child($child->PID, "on_child_signal");
    $worker_child->setChildWheel($child);
    $self->{children_by_wid}->{$child->ID} = $worker_child;
    $self->{children_by_pid}->{$child->PID} = $worker_child;
    $worker_child->put();
}

sub _sessionStdout {
    my ($self, $output, $wheel_id) = @_[OBJECT, ARG0, ARG1];
    $self->{children_by_wid}->{$wheel_id}->pushOutput($output);
}

sub _sessionStderr {
    my ($self, $output, $wheel_id) = @_[OBJECT, ARG0, ARG1];
    printf STDERR (">> From WorkerChild WID=%d: %s\n", $wheel_id, $output);
}

sub _sessionChildSignal {
    my ($self, $pid) = @_[OBJECT, ARG1];
    my $worker_child = $self->{children_by_pid}->{$pid};
    $worker_child->report();
    delete $self->{children_by_wid}->{$worker_child->ID};
    delete $self->{children_by_pid}->{$pid};
}



1;



