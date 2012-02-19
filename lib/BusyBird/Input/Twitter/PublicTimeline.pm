package BusyBird::Input::Twitter::PublicTimeline;

use strict;
use warnings;
use base ('BusyBird::Input::Twitter');

sub _setParams {
    my ($self, $params_ref) = @_;
    $self->SUPER::_setParams($params_ref);
    $self->{no_cache} = 1;
    $self->{page_max} = 1;
}

sub _getWorkerInput {
    my ($self, $count, $page) = @_;
    return {method => 'public_timeline', context => 's'};
}

1;
