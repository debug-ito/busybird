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
    ## return $self->{nt}->list_statuses({
    ##     user => $self->{owner_name},
    ##     list_id => $self->{list_slug_name},
    ##     per_page => $count,
    ##     page => $page,
    ##                                   });
    return {method => 'list_statuses', context => 's',
            args => [{
                user => $self->{owner_name},
                list_id => $self->{list_slug_name},
                per_page => $count,
                page => $page + 1}]};
}

1;
