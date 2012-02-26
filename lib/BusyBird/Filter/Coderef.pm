package BusyBird::Filter::Coderef;
use base ("BusyBird::Filter");

use strict;
use warnings;

use POE;
use BusyBird::CallStack;

sub _setParams {
    my ($self, $param_ref) = @_;
    $self->_setParam($param_ref, 'coderef', undef, 1);
}

sub execute {
    my ($self, $callstack, $ret_session, $ret_event, $statuses) = @_;
    $self->{coderef}->($statuses);
    POE::Kernel->post($ret_session, $ret_event, $callstack, $statuses);
}

1;
