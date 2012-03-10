package BusyBird::Input::Twitter::Search;
use base ('BusyBird::Input::Twitter');
use strict;
use warnings;

sub _setParams {
    my ($self, $params_ref) = @_;
    $self->SUPER::_setParams($params_ref);
    $self->_setParam($params_ref, 'query', undef, 1);
    $self->_setParam($params_ref, 'lang', undef);
}

sub _getWorkerInput {
    my ($self, $count, $page) = @_;
    return {method => 'search', context => 's',
            args => [{
                q => $self->{query},
                lang => $self->{lang},
                rpp => $count,
                page => $page + 1,
            }]};
}

sub _extractStatusesFromWorkerData {
    my ($self_class, $worker_data) = @_;
    my @statuses = map { BusyBird::Status::Twitter->new($_) } @{$worker_data->{results}};
    return \@statuses;
}

1;



