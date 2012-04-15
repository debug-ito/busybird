package BusyBird::Worker::Object;
use strict;
use warnings;
## use POE qw(Filter::Reference);
use AnyEvent;
use AnyEvent::Util;

sub STATUS_OK { 0 };
sub STATUS_NO_METHOD { 1 };
sub STATUS_METHOD_DIES { 2 };


sub _CONTEXT_LIST   { 0 };
sub _CONTEXT_SCALAR { 1 };

## sub _makeOutputObject {
##     my ($status, $data) = @_;
##     return {status => $status, data => $data};
## }

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

## 
##     
##     my $self = $class->SUPER::new(
##         Program => sub {
##             ## POE::Kernel->stop();
##             my $input_str;
##             {
##                 local $/ = undef;
##                 $input_str = <STDIN>;
##             }
##             my $filter = POE::Filter::Reference->new();
##             my $command_objs = $filter->get([$input_str]);
##             
##             my $output_obj = [];
##             foreach my $command (@$command_objs) {
##                 my ($method_name, $args_array, $context_str) = ($command->{method}, $command->{args}, $command->{context});
##                 my $context = &_getContextID($context_str);
##                 if(!$target_object->can($method_name)) {
##                     my $error_msg = sprintf ("ERROR: Method %s is undefined on %s.", $method_name, ref($target_object));
##                     print STDERR ("$error_msg\n");
##                     push(@$output_obj, &_makeOutputObject(STATUS_NO_METHOD, $error_msg));
##                     next;
##                 }
##                 my $ret;
##                 eval {
##                     if($context == _CONTEXT_SCALAR) {
##                         my $return_val = $target_object->$method_name(@$args_array);
##                         $ret = &_makeOutputObject(STATUS_OK, $return_val);
##                     }else {
##                         my @return_vals = $target_object->$method_name(@$args_array);
##                         $ret = &_makeOutputObject(STATUS_OK, \@return_vals);
##                     }
##                 };
##                 if($@) {
##                     printf STDERR ("ERROR: %s::%s: %s", ref($target_object), $method_name, $@);
##                     push(@$output_obj, &_makeOutputObject(STATUS_METHOD_DIES, $@));
##                     next;
##                 }
##                 push(@$output_obj, $ret);
##             }
##             my $serialized_chunks = $filter->put($output_obj);
##             foreach my $chunk (@$serialized_chunks) {
##                 print $chunk;
##             }
##         },
##         StdinFilter  => POE::Filter::Reference->new(),
##         StdoutFilter => POE::Filter::Reference->new(),
##     );
##     $self->{target_object} = $target_object;
##     return $self;
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

