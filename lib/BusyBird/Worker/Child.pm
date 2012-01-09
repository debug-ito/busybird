package BusyBird::Worker::Child;

use strict;
use warnings;
use POE;

sub new {
    my ($class, $receiver_session_id, $receiver_event_name, $input_obj) = @_;
    my $self = bless {
        receiver_session_id => $receiver_session_id,
        receiver_event_name => $receiver_event_name,
        input_obj           => $input_obj,
        child_wheel         => undef,
        output_objs         => [],
        exit_status         => 0,
    }, $class;
    return $self;
}

sub setChildWheel {
    my ($self, $wheel) = @_;
    $self->{child_wheel} = $wheel;
}

sub put {
    my ($self, $input) = @_;
    $input = $self->{input_obj} if !defined($input);
    if(defined($input)) {
        $self->{child_wheel}->put($input) 
    }
}

sub endPut {
    my ($self) = @_;
    $self->{child_wheel}->shutdown_stdin();
}

sub pushOutput {
    my ($self, $output) = @_;
    push(@{$self->{output_objs}}, $output);
}

sub setExitStatus {
    my ($self, $exit_status) = @_;
    $self->{exit_status} = $exit_status;
}

sub report {
    my ($self) = @_;
    POE::Kernel->post($self->{receiver_session_id}, $self->{receiver_event_name}, $self->{output_objs}, $self->{input_obj}, $self->{exit_status});
    $self->{output_objs} = [];
    $self->{exit_status} = 0;
}

sub ID {
    return $_[0]->{child_wheel}->ID;
}

sub PID {
    return $_[0]->{child_wheel}->PID;
}


1;
