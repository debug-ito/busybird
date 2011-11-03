package BusyBird::Output;

use Encode;
use strict;
use warnings;
use DateTime;

## use Data::Dumper;


use BusyBird::Judge;

sub new() {
    my ($class, $name) = @_;
    my $self = {
        name => $name,
        statuses => [],
        status_ids => {},
        judge => undef,
        agents => [],
    };
    return bless $self, $class;
}

sub judge() {
    my ($self, $judge) = @_;
    return $self->{judge} if !defined($judge);
    $self->{judge} = $judge;
}

sub agents() {
    my ($self, @agents) = @_;
    return $self->{agents} if !@agents;
    push(@{$self->{agents}}, @agents);
}

sub _uniqNewStatuses() {
    my ($self, $new_statuses) = @_;
    ## my %ids = ();
    ## foreach my $status (@{$self->{statuses}}) {
    ##     ## print STDERR Dumper($status);
    ##     $ids{$status->{bb_id}} = 1;
    ## }
    my $uniq_statuses = [];
    foreach my $status (@$new_statuses) {
        if(!defined($self->{status_ids}{$status->{bb_id}})) {
            push(@$uniq_statuses, $status);
        }
    }
    return $uniq_statuses;
}

sub _sort() {
    my ($self) = @_;
    my @new_statuses = sort {$b->{bb_datetime}->epoch <=> $a->{bb_datetime}->epoch} @{$self->{statuses}};
    $self->{statuses} = \@new_statuses;
}

sub pushStatuses() {
    my ($self, $statuses) = @_;
    $statuses = $self->_uniqNewStatuses($statuses);
    $self->{judge}->addScore($statuses);
    unshift(@{$self->{statuses}}, @$statuses);
    foreach my $status (@$statuses) {
        $self->{status_ids}{$status->{bb_id}} = 1;
    }
    $self->_sort();
    ## ** we should do classification here

    $self->flushStatuses();
}

sub flushStatuses() {
    my ($self) = @_;
    my $flushed_statuses = $self->{statuses};
    $self->{statuses} = [];
    foreach my $agent (@{$self->{agents}}) {
        $agent->addOutput($self->{name}, $flushed_statuses);
    }
}

1;
