package BusyBird::Input::Twitter::HomeTimeline;

use strict;
use warnings;
use base ('BusyBird::Input::Twitter');

sub _getWorkerInput {
    my ($self, $count, $page) = @_;
    ## return $self->{nt}->home_timeline({count => $count, page => $page});
    return {method => 'home_timeline', context => 'scalar', args => [{
        count => $count,
        page => $page + 1,
        include_entities => 1,
    }]};
}

1;
