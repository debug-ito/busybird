package BusyBird::Worker::Object;
use strict;
use warnings;
use AnyEvent;
use AnyEvent::Util;

sub STATUS_OK { 0 };
sub STATUS_NO_METHOD { 1 };
sub STATUS_METHOD_DIES { 2 };


sub _CONTEXT_LIST   { 0 };
sub _CONTEXT_SCALAR { 1 };

sub _getContextID {
    my ($context_str) = @_;
    return _CONTEXT_LIST if !defined($context_str);
    $context_str = lc($context_str);
    if($context_str eq 's' || $context_str eq 'scalar') {
        return _CONTEXT_SCALAR;
    }
    return _CONTEXT_LIST;
}

sub new {
    my ($class, $target_object) = @_;
    my $self = bless {
        target_object => $target_object,
    }, $class;
    return $self;
}

sub getTargetObject {
    my ($self) = @_;
    return $self->{target_object};
}

sub startJob {
    my ($self, %params) = @_;
    if(!defined($params{method})) {
        die "No method param.";
    }
    if(!defined($params{cb})) {
        die "No cb param.";
    }
    my $target_object = $self->{target_object};
    fork_call {
        my ($method_name, $args_array, $context_str) = @params{qw(method args context)};
        my $context = &_getContextID($context_str);
        if(!$target_object->can($method_name)) {
            my $error_msg = sprintf ("ERROR: Method %s is undefined on %s.", $method_name, ref($target_object));
            ## print STDERR ("$error_msg\n");
            return (STATUS_NO_METHOD, $error_msg);
        }
        $args_array = [] if !defined($args_array);
        my @ret = ();
        eval {
            if($context == _CONTEXT_SCALAR) {
                @ret = (STATUS_OK, scalar($target_object->$method_name(@$args_array)));
            }else {
                @ret = (STATUS_OK, $target_object->$method_name(@$args_array));
            }
        };
        if($@) {
            ## printf STDERR ("ERROR: %s::%s: %s", ref($target_object), $method_name, $@);
            return (STATUS_METHOD_DIES, $@);
        }
        return @ret;
    } $params{cb};
}


1;

