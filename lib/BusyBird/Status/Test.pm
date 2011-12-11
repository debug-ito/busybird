package BusyBird::Status::Test;
use strict;
use warnings;
use base ('BusyBird::Status');

sub new {
    my ($class, %params) = @_;
    return bless \%params, $class;
}

sub AUTOLOAD {
    my $self = shift;
    our $AUTOLOAD;
    return if $AUTOLOAD =~ /::DESTROY$/;
    if($AUTOLOAD !~ /::get(.+?)$/) {
        die "Method " . $AUTOLOAD . " is undefined.";
    }
    my $param_name = $1;
    if(!defined($self->{$param_name})) {
        die "Parameter " . $param_name . " is undefined.";
    }
    return $self->{$param_name};
}

sub setScore {
    my ($self, $score) = @_;
    return ($self->{Score} = $score);
}

sub setInputName {
    my ($self, $input_name) = @_;
    return ($self->{InputName} = $input_name);
}

1;

