package BusyBird::InputDriver::Twitter::Search;
use base ('BusyBird::InputDriver::Twitter');
use strict;
use warnings;
use BusyBird::Util ('setParam');

sub new {
    my ($class, %params) = @_;
    my $self = $class->SUPER::new(%params);
    $self->setParam(\%params, 'query', undef, 1);
    $self->setParam(\%params, 'lang', undef);
}

sub getWorkerInput {
    my ($self, $count, $page) = @_;
    return {method => 'search', context => 's',
            args => [{
                q => $self->{query},
                lang => $self->{lang},
                rpp => $count,
                page => $page + 1,
            }]};
}

sub extractStatusesFromWorkerData {
    my ($self_class, $worker_data) = @_;
    my @statuses = map { BusyBird::Status::Twitter->new($_) } @{$worker_data->{results}};
    return \@statuses;
}

1;



