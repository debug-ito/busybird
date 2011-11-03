package BusyBird::Timer;

use strict;
use warnings;

sub new() {
    my ($class, $interval) = @_;
    bless {'cur_interval' => $interval}, $class;
}

sub getNextDelay() {
    my ($self) = @_;
    return $self->{cur_interval};
}

sub setInterval() {
    my ($self, $new_interval) = @_;
    $self->{cur_interval} = $new_interval;
}


1;
