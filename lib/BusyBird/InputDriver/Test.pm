package BusyBird::InputDriver::Test;
use strict;
use warnings;

use DateTime;
use BusyBird::Status;
use BusyBird::Log ('bblog');
use AnyEvent;
use BusyBird::Util ('setParam');


my $LOCAL_TZ = DateTime::TimeZone->new( name => 'local' );
my $g_next_serial_num = 0;

sub new {
    my ($class, %params) = @_;
    my $self = bless {}, $class;
    $self->_setParams(\%params);
    return $self;
}

sub _setParams {
    my ($self, $params_ref) = @_;
    $self->setParam($params_ref, 'new_interval', 1);
    $self->setParam($params_ref, 'new_count', 1);
    $self->setParam($params_ref, 'page_num', 1);
    $self->setParam($params_ref, 'load_delay', 0.1);
    $self->{serial_num} = $g_next_serial_num;
    $g_next_serial_num++;
    $self->{fired_count} = -1;
    $self->{timestamp} = undef;
    $self->{input_name} = 'UNKNOWN';
    if(defined($params_ref->{busybird_input})) {
        $self->{input_name} = $params_ref->{busybird_input}->getName();
    }
    
}

sub _newStatus {
    my ($self, $nowtime, $page, $index) = @_;
    my $timestr = $nowtime->strftime('%Y/%m/%d %H:%M:%S');
    my $name = $self->{input_name};
    my $text = qq|{"name": "$name", "time": "$timestr", "page": $page, "index": $index}|;
    my $status_id = 'Test' . $self->{serial_num} ."_"  . $nowtime->epoch . "_${page}_$index";
    my $status = BusyBird::Status->new(
        id => $status_id,
        id_str => $status_id,
        created_at => $nowtime,
        text => $text,
        in_reply_to_screen_name => '',
        user => {
            'screen_name' => 'Test',
            'name' => 'Te st',
            'profile_image_url' => '',
        }
    );
    return $status;
}

sub setTimeStamp {
    my ($self, $ts_datetime) = @_;
    $self->{timestamp} = $ts_datetime;
}

sub getStatusesPage {
    my ($self, $count, $page, $callback) = @_;
    ## &bblog($callstack->toString());
    my $tw; $tw = AnyEvent->timer(
        after => $self->{load_delay},
        cb => sub {
            undef $tw;
            if($page == 0) {
                $self->{fired_count} = ($self->{fired_count} + 1) % $self->{new_interval};
            }
            if($page >= $self->{page_num} || $self->{fired_count} != 0) {
                $callback->();
                return;
            }
            my @ret = ();
            my $timestamp = defined($self->{timestamp}) ? $self->{timestamp}->clone() : DateTime->now();
            $timestamp->set_time_zone($LOCAL_TZ);
            for(my $i = 0 ; $i < $self->{new_count} ; $i++) {
                push(@ret, $self->_newStatus($timestamp, $page, $i));
            }
            ## $callstack->pop(\@ret);
            $callback->(\@ret);
        },
    );
}

1;
