package Pseudo::CV;
use strict;
use warnings;
use EV;

sub new {
    my ($class) = @_;
    return bless {
        count => 0,
    }, $class;
}

sub recv {
    EV::run;
}

sub send {
    EV::break;
}

sub begin {
    my ($self) = @_;
    $self->{count}++;
}

sub end {
    my ($self) = @_;
    $self->{count}-- if $self->{count} > 0;
    if($self->{count} == 0) {
        $self->send;
    }
}

1;
