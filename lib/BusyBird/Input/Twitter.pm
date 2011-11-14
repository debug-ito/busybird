package BusyBird::Input::Twitter;
use base ('BusyBird::Input');

use strict;
use warnings;
use BusyBird::Status::Twitter;

sub _setParams {
    my ($self, $params_ref) = @_;
    $self->SUPER::_setParams($params_ref);
    $self->_setParam($params_ref, 'nt', undef, 1);
}

sub _getTimeline {
    my ($self, $count, $page) = @_;
    ## MUST BE INPLEMENTED IN SUBCLASSES
    return undef;
}

sub _getStatuses {
    my ($self, $count, $page) = @_;
    my $timeline = $self->_getTimeline($count, $page);
    printf STDERR ("DEBUG: Got %d tweets from input %s\n", int(@$timeline), $self->getName());
    return undef if !$timeline;
    ## foreach my $status (@$timeline) {
    ##     push(@$ret_stats, BusyBird::Status::Twitter->new($status));
    ## }
    my @ret_stats = map { BusyBird::Status::Twitter->new($_) } @$timeline;
    return \@ret_stats;
}

1;
