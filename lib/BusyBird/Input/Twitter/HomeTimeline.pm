package BusyBird::Input::Twitter::HomeTimeline;

use strict;
use warnings;
use base ('BusyBird::Input::Twitter');

sub _getTimeline {
    my ($self, $count, $page) = @_;
    return $self->{nt}->home_timeline({count => $count, page => $page});
}

1;
