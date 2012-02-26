package BusyBird::Input::Test;
use base ('BusyBird::Input');
use strict;
use warnings;

use DateTime;
use POE;
use BusyBird::Status::Test;
use BusyBird::CallStack;
use BusyBird::Log ('bblog');

my $LOCAL_TZ = DateTime::TimeZone->new( name => 'local' );

sub _setParams {
    my ($self, $params_ref) = @_;
    $self->SUPER::_setParams($params_ref);
    $self->_setParam($params_ref, 'new_interval', 1);
    $self->_setParam($params_ref, 'new_count', 1);
    $self->_setParam($params_ref, 'fired_count', 0);
}

sub _newStatus {
    my ($self, $nowtime, $index) = @_;
    return BusyBird::Status::Test->new(
        'ID'   => 'Test' . $nowtime->epoch . "_$index",
        'Text' => 'Now ' . $nowtime->strftime('%Y/%m/%d %H:%M:%S') . ", part $index !!",
        'DateTime' => $nowtime,
        'SourceName'    => 'Test',
        'SourceNameAlt' => 'Te st',
        'IconURL' => '',
        'ReplyToName' => '');
}

sub _getStatuses {
    my ($self, $callstack, $ret_session, $ret_event, $count, $page) = @_;
    $callstack = BusyBird::CallStack->newStack($callstack, $ret_session, $ret_event, count => $count, page => $page);

    &bblog("Input::Test::_getStatus(ret_session => $ret_session, ret_event => $ret_event, count => $count, page => $page)");
    &bblog($callstack->toString());

    if($page > 0) {
        $callstack->pop(undef);
        return;
    }

    $self->{fired_count}++;
    if($self->{fired_count} < $self->{new_interval}) {
        $callstack->pop(undef);
        return;
    }
    $self->{fired_count} = 0;
    my @ret = ();
    my $nowtime = DateTime->now();
    $nowtime->set_time_zone($LOCAL_TZ);
    for(my $i = 0 ; $i < $self->{new_count} ; $i++) {
        push(@ret, $self->_newStatus($nowtime, $i));
    }

    &bblog(sprintf("Input::Test::_getStatus: %d statuses are reported.", int(@ret)));
    $callstack->pop(\@ret);

    ### #### 
    ### my ($self, $count, $page) = @_;
    ### $self->{fired_count}++;
    ### return undef if $self->{fired_count} <= $self->{new_interval};
    ### $self->{fired_count} = 0;
    ### if($page > 0) {
    ###     return undef;
    ### }
    ### my @ret = ();
    ### my $nowtime = DateTime->now();
    ### $nowtime->set_time_zone($LOCAL_TZ);
    ### for(my $i = 0 ; $i < $self->{new_count} ; $i++) {
    ###     push(@ret, $self->_newStatus($nowtime, $i));
    ### }
    ### return \@ret;
}

1;
