package BusyBird::Input::Twitter;
use base ('BusyBird::Input');

use strict;
use warnings;
use POE;
use BusyBird::Status::Twitter;
use BusyBird::Worker::Object;
use BusyBird::Log ('bblog');

use Data::Dumper;

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
    my @statuses = map { BusyBird::Status::Twitter->new($_) } @$worker_data;
    return \@statuses;
}

sub _getStatuses {
    my ($self, $callstack, $ret_session, $ret_event, $count, $page) = @_;
    my $worker_input = $self->_getWorkerInput($count, $page);
    if(!$worker_input) {
        POE::Kernel->post($ret_session, $ret_event, $callstack, undef);
        return;
    }
    BusyBird::CallStack->newStack($callstack, $ret_session, $ret_event, count => $count, page => $page);
    $self->{worker}->startJob($callstack, $self->{session}, 'on_worker_complete', $worker_input);
    return;
    
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

sub _sessionStart {
    my ($self, $kernel) = @_[OBJECT, KERNEL];
    $self->SUPER::_sessionStart(@_[1 .. $#_]);
    $kernel->state('on_worker_complete', $self, '_sessionOnWorkerComplete');
}

sub _sessionOnWorkerComplete {
    my ($self, $kernel, $callstack, $output_objs, $input_obj, $exit_status) = @_[OBJECT, KERNEL, ARG0 .. ARG3];
    ## print STDERR ("BusyBird::Input::Twitter: Worker complate!------\n");
    ## print STDERR (Dumper($output_objs));
    ## print STDERR ("-----------------\n");
    my ($worker_status, $worker_data) = ($output_objs->[0]->{status}, $output_objs->[0]->{data});
    if($worker_status != BusyBird::Worker::Object::STATUS_OK) {
        &bblog(sprintf("WARNING: Twitter worker returns worker_status %d", $worker_status));
        $callstack->pop(undef);
        return;
    }
    &bblog(sprintf("DEBUG: Got %d tweets from input %s", int(@$worker_data), $self->getName()));
    $callstack->pop($self->_extractStatusesFromWorkerData($worker_data));
}

1;
