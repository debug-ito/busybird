package BusyBird::InputDriver::Twitter;
use strict;
use warnings;


use Carp;
use BusyBird::Status;
use BusyBird::Worker::Twitter;
use BusyBird::Log ('bblog');
use BusyBird::Util qw(setParam :datetime);

our %MONTH = (
    Jan => 1, Feb => 2,  Mar =>  3, Apr =>  4,
    May => 5, Jun => 6,  Jul =>  7, Aug =>  8,
    Sep => 9, Oct => 10, Nov => 11, Dec => 12,
);

sub new {
    my ($class, %params) = @_;
    my $self = bless {}, $class;
    $self->_setParams(\%params);
    return $self;
}

sub _setParams {
    my ($self, $params_ref) = @_;
    $self->setParam($params_ref, 'worker', undef, 1);
    $self->{max_id_for_page} = [];
}

## sub convertNormalDateTime {
##     my ($class_self, $time_str) = @_;
##     my ($weekday, $monthname, $day, $time, $timezone, $year) = split(/\s+/, $time_str);
##     my ($hour, $minute, $second) = split(/:/, $time);
##     my $dt = DateTime->new(
##         year      => $year,
##         month     => $MONTH{$monthname},
##         day       => $day,
##         hour      => $hour,
##         minute    => $minute,
##         second    => $second,
##         time_zone => $timezone
##     );
##     return $dt;
## }

## sub processEntities {
##     my ($class_self, $text, $entities) = @_;
##     if(!defined($entities)) {
##         return $text;
##     }
##     if(defined($entities->{media})) {
##         foreach my $entity (@{$entities->{media}}) {
##             $text = $class_self->entityExpandURL($text, $entity);
##         }
##     }
##     if(defined($entities->{urls})) {
##         foreach my $entity (@{$entities->{urls}}) {
##             $text = $class_self->entityExpandURL($text, $entity);
##         }
##     }
##     return $text;
## }

## sub entityExpandURL {
##     my ($class_self, $text, $entity) = @_;
##     if(!defined($entity) || !defined($entity->{expanded_url}) || !defined($entity->{indices})) {
##         return $text;
##     }
##     if(ref($entity->{indices}) ne 'ARRAY' || int(@{$entity->{indices}}) < 2) {
##         return $text;
##     }
##     if($entity->{indices}->[1] < $entity->{indices}->[0]) {
##         return $text;
##     }
##     substr($text, $entity->{indices}->[0], $entity->{indices}->[1] - $entity->{indices}->[0]) = $entity->{expanded_url};
##     return $text;
## }

sub getWorkerInput {
    my ($self, $count, $page) = @_;
    ## MUST BE IMPLEMENTED IN SUBCLASSES
    return undef;
}

sub createStatusID {
    my ($self, $nt_status, $id_key_base) = @_;
    my $str_key = "${id_key_base}_str";
    my $orig_id = (defined($nt_status->{$str_key}) ? $nt_status->{$str_key} : $nt_status->{$id_key_base});
    if(!defined($orig_id)) {
        return undef;
    }
    return 'Twitter_' . $self->{worker}->getAPIURL() . "_" . $orig_id;
}

sub convertNormalStatus {
    my ($self, $nt_status) = @_;
    ## my $text = $self->processEntities($nt_status->{text}, $nt_status->{entities});
    my $text = $nt_status->{text};
    my $status_id = $self->createStatusID($nt_status, 'id');
    my $status_rep_id = $self->createStatusID($nt_status, 'in_reply_to_status_id');
    return BusyBird::Status->new(
        id => $status_id,
        id_str => defined($status_id) ? "$status_id" : undef,
        ## created_at => $self->convertNormalDateTime($nt_status->{created_at}),
        created_at => datetimeNormalize($nt_status->{created_at}, 1),
        text => $text,
        in_reply_to_screen_name => $nt_status->{in_reply_to_screen_name},
        in_reply_to_status_id => $status_rep_id,
        in_reply_to_status_id_str => defined($status_rep_id) ? "$status_rep_id" : undef,
        user => {
            'screen_name' => $nt_status->{user}->{screen_name},
            'name' => $nt_status->{user}->{name},
            'profile_image_url' => $nt_status->{user}->{profile_image_url},
        },
        entities => $nt_status->{entities},
        busybird => {
            original => {
                map { $_ => $nt_status->{$_} } qw(id id_str in_reply_to_status_id in_reply_to_status_id_str),
            },
        },
    );
}

sub extractStatusesFromWorkerData {
    my ($self, $worker_data) = @_;
    my @statuses = ();
    foreach my $nt_status (@$worker_data) {
        push(@statuses, $self->convertNormalStatus($nt_status));
    }
    return \@statuses;
}

sub _logWorkerInput {
    my ($self, $worker_input) = @_;
    my $argref = $worker_input->{args}->[0];
    &bblog(sprintf(
        "%s: method: %s, args: %s", __PACKAGE__, $worker_input->{method},
        join(", ", map {"$_: " . (defined($argref->{$_}) ? $argref->{$_} : "[undef]")} keys %$argref)
    ));
}

sub getStatusesPage {
    my ($self, $count, $page, $callback) = @_;
    if($page <= 0) {
        @{$self->{max_id_for_page}} = ();
    }elsif(!defined($self->{max_id_for_page}[$page])) {
        &bblog(sprintf("%s: max_id for page $page is undefined. Something's wrong.", __PACKAGE__));
        $callback->(undef);
        return;
    }
    my $worker_input = $self->getWorkerInput($count, $page);
    if(!$worker_input) {
        $callback->(undef);
        return;
    }
    $self->_logWorkerInput($worker_input);
    $worker_input->{cb} = sub {
        my ($status, @data) = @_;
        if($status != BusyBird::Worker::Object::STATUS_OK) {
            $data[0] = "undef" if !defined($data[0]);
            &bblog(sprintf("WARNING: Twitter worker returns status %d: %s", $status, $data[0]));
            $callback->(undef);
            return;
        }
        my $bb_status = $self->extractStatusesFromWorkerData($data[0]);
        if(@$bb_status) {
            $self->{max_id_for_page}->[$page + 1] = $bb_status->[$#$bb_status]->{busybird}{original}{id_str};
        }
        $callback->($bb_status);
    };
    $self->{worker}->startJob(%$worker_input);
}

sub fetchStatus {
    my ($self, $status_id, $callback) = @_;
    $self->{worker}->startJob(
        method => 'show_status',
        args => [{id => $status_id, include_entities => 1}],
        cb => sub {
            my ($status, $data) = @_;
            if($status != BusyBird::Worker::Object::STATUS_OK) {
                &bblog("WARNING: fetchStatus(): Twitter worker returns $status.");
                $callback->(undef);
                return;
            }
            $callback->($self->convertNormalStatus($data));
        }
    );
}


1;
