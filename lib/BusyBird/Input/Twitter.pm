package BusyBird::Input::Twitter;
use base ('BusyBird::Input');

use strict;
use warnings;
use BusyBird::Status;
use BusyBird::Worker::Twitter;
use BusyBird::Log ('bblog');

our %MONTH = (
    Jan => 1, Feb => 2,  Mar =>  3, Apr =>  4,
    May => 5, Jun => 6,  Jul =>  7, Aug =>  8,
    Sep => 9, Oct => 10, Nov => 11, Dec => 12,
);

sub _timeStringToDateTime() {
    my ($class_self, $time_str) = @_;
    my ($weekday, $monthname, $day, $time, $timezone, $year) = split(/\s+/, $time_str);
    my ($hour, $minute, $second) = split(/:/, $time);
    my $dt = DateTime->new(
        year      => $year,
        month     => $MONTH{$monthname},
        day       => $day,
        hour      => $hour,
        minute    => $minute,
        second    => $second,
        time_zone => $timezone
    );
    return $dt;
}

sub _processEntities {
    my ($class_self, $text, $entities) = @_;
    if(!defined($entities)) {
        return $text;
    }
    if(defined($entities->{media})) {
        foreach my $entity (@{$entities->{media}}) {
            $text = $class_self->_entityExpandURL($text, $entity);
        }
    }
    if(defined($entities->{urls})) {
        foreach my $entity (@{$entities->{urls}}) {
            $text = $class_self->_entityExpandURL($text, $entity);
        }
    }
    return $text;
}

sub _entityExpandURL {
    my ($class_self, $text, $entity) = @_;
    if(!defined($entity) || !defined($entity->{expanded_url}) || !defined($entity->{indices})) {
        return $text;
    }
    if(ref($entity->{indices}) ne 'ARRAY' || int(@{$entity->{indices}}) < 2) {
        return $text;
    }
    if($entity->{indices}->[1] < $entity->{indices}->[0]) {
        return $text;
    }
    substr($text, $entity->{indices}->[0], $entity->{indices}->[1] - $entity->{indices}->[0]) = $entity->{expanded_url};
    return $text;
}

sub _setParams {
    my ($self, $params_ref) = @_;
    $self->SUPER::_setParams($params_ref);
    $self->_setParam($params_ref, 'worker', undef, 1);
}

## sub _getTimeline {
##     my ($self, $count, $page) = @_;
##     ## MUST BE IMPLEMENTED IN SUBCLASSES
##     return undef;
## }

sub _getWorkerInput {
    my ($self, $count, $page) = @_;
    ## MUST BE IMPLEMENTED IN SUBCLASSES
    return undef;
}

sub _extractStatusesFromWorkerData {
    my ($self_class, $worker_data) = @_;
    my @statuses = ();
    foreach my $nt_status (@$worker_data) {
        my $text = $self_class->_processEntities($nt_status->{text}, $nt_status->{entities});
        my $status = BusyBird::Status->new();
        $status->setDateTime($self_class->_timeStringToDateTime($nt_status->{created_at}));
        $status->set(
            id => 'Twitter' . $nt_status->{id},
            text => $text,
            in_reply_to_screen_name => $nt_status->{in_reply_to_screen_name},
            'user/screen_name' => $nt_status->{user}->{screen_name},
            'user/name' => $nt_status->{user}->{name},
            'user/profile_image_url' => $nt_status->{user}->{profile_image_url},
        );
        push(@statuses, $status);
    }
    ## my @statuses = map { BusyBird::Status::Twitter->new($_) } @$worker_data;
    return \@statuses;
}

sub _getStatusesPage {
    my ($self, $count, $page, $callback) = @_;
    my $worker_input = $self->_getWorkerInput($count, $page);
    if(!$worker_input) {
        $callback->(undef);
        return;
    }
    $worker_input->{cb} = sub {
        my ($status, @data) = @_;
        if($status != BusyBird::Worker::Object::STATUS_OK) {
            &bblog(sprintf("WARNING: Twitter worker returns status %d", $status));
            $callback->(undef);
            return;
        }
        $callback->($self->_extractStatusesFromWorkerData($data[0]));
    };
    $self->{worker}->startJob(%$worker_input);

    ## my ($self, $callstack, $ret_session, $ret_event, $count, $page) = @_;
    ## my $worker_input = $self->_getWorkerInput($count, $page);
    ## if(!$worker_input) {
    ##     POE::Kernel->post($ret_session, $ret_event, $callstack, undef);
    ##     return;
    ## }
    ## BusyBird::CallStack->newStack($callstack, $ret_session, $ret_event, count => $count, page => $page);
    ## $self->{worker}->startJob($callstack, $self->{session}, 'on_worker_complete', $worker_input);
    ## return;
    
    ## my ($self, $count, $page) = @_;
    ## my $timeline = $self->_getTimeline($count, $page);
    ## printf STDERR ("DEBUG: Got %d tweets from input %s\n", int(@$timeline), $self->getName());
    ## return undef if !$timeline;
    ## ## foreach my $status (@$timeline) {
    ## ##     push(@$ret_stats, BusyBird::Status::Twitter->new($status));
    ## ## }
    ## my @ret_stats = map { BusyBird::Status::Twitter->new($_) } @$timeline;
    ## return \@ret_stats;
}

## sub _sessionStart {
##     my ($self, $kernel) = @_[OBJECT, KERNEL];
##     $self->SUPER::_sessionStart(@_[1 .. $#_]);
##     $kernel->state('on_worker_complete', $self, '_sessionOnWorkerComplete');
## }
## 
## sub _sessionOnWorkerComplete {
##     my ($self, $kernel, $callstack, $output_objs, $input_obj, $exit_status) = @_[OBJECT, KERNEL, ARG0 .. ARG3];
##     ## print STDERR ("BusyBird::Input::Twitter: Worker complate!------\n");
##     ## print STDERR (Dumper($output_objs));
##     ## print STDERR ("-----------------\n");
##     my ($worker_status, $worker_data) = ($output_objs->[0]->{status}, $output_objs->[0]->{data});
##     if($worker_status != BusyBird::Worker::Object::STATUS_OK) {
##         &bblog(sprintf("WARNING: Twitter worker returns worker_status %d", $worker_status));
##         $callstack->pop(undef);
##         return;
##     }
##     &bblog(sprintf("DEBUG: Got %d tweets from input %s", int(@$worker_data), $self->getName()));
##     $callstack->pop($self->_extractStatusesFromWorkerData($worker_data));
## }

1;
