package BusyBird::InputDriver::Twitter::List;

use strict;
use warnings;
use base ('BusyBird::InputDriver::Twitter');
use BusyBird::Util ('setParam');

sub new {
    my ($class, %params) = @_;
    my $self = $class->SUPER::new(%params);
    $self->setParam(\%params, 'owner_name', undef, 1);
    $self->setParam(\%params, 'list_slug_name', undef, 1);
    return $self;
}

sub getWorkerInput {
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
