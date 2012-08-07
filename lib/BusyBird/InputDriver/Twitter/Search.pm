package BusyBird::InputDriver::Twitter::Search;
use base ('BusyBird::InputDriver::Twitter');
use strict;
use warnings;

use DateTime;
use BusyBird::Util qw(setParam :datetime);
use BusyBird::Status;

sub new {
    my ($class, %params) = @_;
    my $self = $class->SUPER::new(%params);
    $self->setParam(\%params, 'query', undef, 1);
    $self->setParam(\%params, 'lang', undef);
    $self->setParam(\%params, 'result_type', 'mixed');
    return $self;
}

sub getWorkerInput {
    my ($self, $count, $page) = @_;
    my %argset = (
        q => $self->{query},
        rpp => $count,
        page => $page + 1,
        include_entities => 1,
        result_type => $self->{result_type},
    );
    $argset{lang} = $self->{lang} if $self->{lang};
    return {method => 'search', context => 's',
            args => [\%argset]};
}

## sub convertSearchDateTime {
##     my ($self_class, $time_str) = @_;
##     my ($weekday, $day, $monthname, $year, $time, $timezone) = split(/[\s,]+/, $time_str);
##     my ($hour, $minute, $second) = split(/:/, $time);
##     my $dt = DateTime->new(
##         year      => $year,
##         month     => $BusyBird::InputDriver::Twitter::MONTH{$monthname},
##         day       => $day,
##         hour      => $hour,
##         minute    => $minute,
##         second    => $second,
##         time_zone => $timezone
##     );
##     return $dt;
## 
## }

sub convertSearchStatus {
    my ($self, $nt_search_status) = @_;
    my $text = $self->processEntities($nt_search_status->{text}, $nt_search_status->{entities});
    my $id = $self->createStatusID($nt_search_status, 'id');
    return BusyBird::Status->new(
        id => $id,
        id_str => defined($id) ? "$id" : undef,
        ## created_at => $self->convertSearchDateTime($nt_search_status->{created_at}),
        created_at => datetimeNormalize($nt_search_status->{created_at}, 1),
        text => $text,
        user => {
            screen_name => $nt_search_status->{from_user},
            name => $nt_search_status->{from_user_name},
            profile_image_url => $nt_search_status->{profile_image_url},
            busybird => {
                original => {
                    map {$_ => $nt_search_status->{$_}} qw(id id_str),
                }
            }
        },
        entities => $nt_search_status->{entities},
    );
}

sub extractStatusesFromWorkerData {
    my ($self, $worker_data) = @_;
    my @statuses = ();
    if(!defined($worker_data) || !defined($worker_data->{results})) {
        return \@statuses;
    }
    foreach my $search_status (@{$worker_data->{results}}) {
        push(@statuses, $self->convertSearchStatus($search_status));
    }
    return \@statuses;
}

1;



