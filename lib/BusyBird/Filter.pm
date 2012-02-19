package BusyBird::Filter;

use strict;
use warnings;
use POE;

use BusyBird::CallStack;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub execute {
    my ($self, $callstack, $ret_session, $ret_event, $statuses) = @_;
    ## MUST BE IMPLEMENTED IN SUBCLASSES
    POE::Kernel->post($ret_session, $ret_event, $callstack, $statuses);
}

1;



