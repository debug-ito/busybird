package BusyBird::InputDriver::Twitter::PublicTimeline;

use strict;
use warnings;
use base ('BusyBird::InputDriver::Twitter');

sub getWorkerInput {
    my ($self, $count, $page) = @_;
    return undef if $page > 0;
    return {method => 'public_timeline', context => 's', args => [{include_entities => 1}]};
}

1;
