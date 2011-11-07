package BusyBird::Output;

use Encode;
use strict;
use warnings;
use DateTime;

## use Data::Dumper;


use BusyBird::Judge;

sub new {
    my ($class, $name) = @_;
    my $self = {
        name => $name,
        new_statuses => [],
        old_statuses => [],
        status_ids => {},
        judge => undef,
        agents => [],
    };
    return bless $self, $class;
}

sub judge {
    my ($self, $judge) = @_;
    return $self->{judge} if !defined($judge);
    $self->{judge} = $judge;
}

sub agents {
    my ($self, @agents) = @_;
    return $self->{agents} if !@agents;
    push(@{$self->{agents}}, @agents);
}

sub _uniqStatuses {
    my ($self, $statuses) = @_;
    ## my %ids = ();
    ## foreach my $status (@{$self->{statuses}}) {
    ##     ## print STDERR Dumper($status);
    ##     $ids{$status->{bb_id}} = 1;
    ## }
    my $uniq_statuses = [];
    foreach my $status (@$statuses) {
        if(!defined($self->{status_ids}{$status->{bb_id}})) {
            push(@$uniq_statuses, $status);
        }
    }
    return $uniq_statuses;
}

sub _sort {
    my ($self) = @_;
    my @sorted_statuses = sort {$b->{bb_datetime}->epoch <=> $a->{bb_datetime}->epoch} @{$self->{new_statuses}};
    $self->{new_statuses} = \@sorted_statuses;
}

sub pushStatuses {
    my ($self, $statuses) = @_;
    $statuses = $self->_uniqStatuses($statuses);
    $self->{judge}->addScore($statuses);
    unshift(@{$self->{new_statuses}}, @$statuses);
    foreach my $status (@$statuses) {
        $self->{status_ids}{$status->{bb_id}} = 1;
    }
    $self->_sort();
    
    ## ** we should do classification here, or it's better to do it in another method??
}

## sub flushStatuses() {
##     my ($self) = @_;
##     my $flushed_statuses = $self->{statuses};
##     $self->{statuses} = [];
##     foreach my $agent (@{$self->{agents}}) {
##         $agent->addOutput($self->{name}, $flushed_statuses);
##     }
## }

1;
