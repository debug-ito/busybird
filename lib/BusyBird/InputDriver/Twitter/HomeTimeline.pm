package BusyBird::InputDriver::Twitter::HomeTimeline;

use strict;
use warnings;
use base ('BusyBird::InputDriver::Twitter');

sub getWorkerInput {
    my ($self, $count, $page) = @_;
    my $args = {
        count => $count,
        include_entities => 1,
    };
    if(defined($self->{max_id_for_page}[$page])) {
        $args->{max_id} = $self->{max_id_for_page}[$page];
    }
    return {method => 'home_timeline', context => 'scalar', args => [$args]};
}

1;
