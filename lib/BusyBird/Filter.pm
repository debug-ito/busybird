package BusyBird::Filter;
use base ("BusyBird::Object");

use strict;
use warnings;
use POE;

use BusyBird::CallStack;

sub new {
    my ($class, %params) = @_;
    my $self = bless {}, $class;
    $self->_setParams(\%params);
    return $self;
}

sub _setParams {
    my ($self, $param_ref) = @_;
    ;
}

sub execute {
    my ($self, $callstack, $ret_session, $ret_event, $statuses) = @_;
    ## MUST BE IMPLEMENTED IN SUBCLASSES
    POE::Kernel->post($ret_session, $ret_event, $callstack, $statuses);
}

1;



