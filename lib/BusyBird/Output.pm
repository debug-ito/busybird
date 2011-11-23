package BusyBird::Output;
use base ('BusyBird::RequestListener');
use Encode;
use strict;
use warnings;
use DateTime;

## use Data::Dumper;
use BusyBird::Judge;

my %COMMAND = (
    NEW_STATUSES => 'new_statuses',
    CONFIRM => 'confirm',
);

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

sub getName {
    my $self = shift;
    return $self->{name};
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
        if(!defined($self->{status_ids}{$status->getID()})) {
            push(@$uniq_statuses, $status);
        }
    }
    return $uniq_statuses;
}

sub _sort {
    my ($self) = @_;
    my @sorted_statuses = sort {$b->getDateTime()->epoch <=> $a->getDateTime()->epoch} @{$self->{new_statuses}};
    $self->{new_statuses} = \@sorted_statuses;
}

sub pushStatuses {
    my ($self, $statuses) = @_;
    $statuses = $self->_uniqStatuses($statuses);
    $self->{judge}->addScore($statuses);
    unshift(@{$self->{new_statuses}}, @$statuses);
    foreach my $status (@$statuses) {
        $self->{status_ids}{$status->getID()} = 1;
    }
    $self->_sort();
    
    ## ** we should do classification here, or it's better to do it in another method??
}

sub _getPointNameForCommand {
    my ($self, $com_name) = @_;
    return '/' . $self->getName() . '/' . $com_name;
}

sub getRequestPoints {
    my ($self) = @_;
    return map { $self->_getPointNameForCommand($_) } (values %COMMAND);
}

sub onCompletePushingStatuses {
    my ($self) = @_;
    BusyBird::HTTPD->replyPoint($self->_getPointNameForCommand($COMMAND{NEW_STATUSES}));
}

sub reply {
    my ($self, $request_point_name, $detail) = @_;
    if($request_point_name !~ m|^/([^/]+)/([^/]+)$|) {
        return ($self->NOT_FOUND);
    }
    my ($output_name, $command) = ($1, $2);
    if($command eq $COMMAND{NEW_STATUSES}) {
        return $self->replyNewStatuses($detail);
    }elsif($command eq $COMMAND{CONFIRM}) {
        return $self->replyConfirm($detail);
    }
}

sub replyNewStatuses {
    my ($self, $detail) = @_;
    if(!@{$self->{new_statuses}}) {
        return ($self->HOLD);
    }
    my $ret = "";
    foreach my $status (@{$self->{new_statuses}}) {
        $ret .= sprintf("Source: %s, Text: %s\n", $status->getSourceName(), $status->getText());
    }
    return ($self->REPLIED, \$ret, "text/plain; charset=UTF-8");
}

sub replyConfirm {
    my ($self, $detail) = @_;
    unshift(@{$self->{old_statuses}}, @{$self->{new_statuses}});
    $self->{new_statuses} = [];
    my $ret = "Confirm OK";
    return ($self->REPLIED, \$ret, "text/plain");
}

1;
