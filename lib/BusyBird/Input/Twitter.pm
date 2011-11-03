package BusyBird::Input::Twitter;

use strict;
use warnings;
use DateTime;
use base ('BusyBird::Input');

my %MONTH = (
    Jan => 1, Feb => 2,  Mar =>  3, Apr =>  4,
    May => 5, Jun => 6,  Jul =>  7, Aug =>  8,
    Sep => 9, Oct => 10, Nov => 11, Dec => 12,
    );

sub _timeStringToDateTime() {
    my ($time_str) = @_;
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

sub _setParams() {
    my ($self, $params_ref) = @_;
    $self->SUPER::_setParams($params_ref);
    $self->_setParam($params_ref, 'nt', undef, 1);
}

sub _getTimeline() {
    my ($self, $count, $page) = @_;
    ## MUST BE INPLEMENTED IN SUBCLASSES
    return undef;
}

sub _getStatuses() {
    my ($self, $count, $page) = @_;
    my $timeline = $self->_getTimeline($count, $page);
    printf STDERR ("DEBUG: Got %d tweets from input %s\n", int(@$timeline), $self->getName());
    my $ret_stats = [];
    return undef if !$timeline;
    foreach my $status (@$timeline) {
        push(@$ret_stats,
             {
                 'bb_id' => 'Twitter' . $status->{id},
                 'bb_text' => $status->{text},
                 'bb_datetime' => &_timeStringToDateTime($status->{created_at}),
                 'bb_source_name' => $status->{user}->{screen_name},
                 'bb_icon_url' => $status->{user}->{profile_image_url},
                 'bb_reply_to_name' => $status->{in_reply_to_screen_name},
             });
    }
    return $ret_stats;
}

1;
