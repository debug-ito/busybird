package BusyBird::Input::Twitter::List;

use strict;
use warnings;
use base ('BusyBird::Input::Twitter');

sub _setParams {
    my ($self, $params_ref) = @_;
    $self->SUPER::_setParams($params_ref);
    $self->_setParam($params_ref, 'owner_name', undef, 1);
    $self->_setParam($params_ref, 'list_slug_name', undef, 1);
}

sub _getWorkerInput {
    my ($self, $count, $page) = @_;
    my $args = {
        user => $self->{owner_name},
        list_id => $self->{list_slug_name},
        per_page => $count,
        include_entities => 1,
    };
    if(defined($self->{max_id_for_page}[$page])) {
        $args->{max_id} = $self->{max_id_for_page}[$page];
    }
    return {method => 'list_statuses', context => 's',
            args => [$args]};
}

1;
