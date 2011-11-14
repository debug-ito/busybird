package BusyBird::Status::Twitter;
use strict;
use warnings;

use Net::Twitter;
use DateTime;

my %MONTH = (
    Jan => 1, Feb => 2,  Mar =>  3, Apr =>  4,
    May => 5, Jun => 6,  Jul =>  7, Aug =>  8,
    Sep => 9, Oct => 10, Nov => 11, Dec => 12,
    );


sub new {
    my ($class, $net_twitter_status) = @_;
    return bless {
        'nt_status' => $net_twitter_status,
        'bb_datetime' =>  $class->_timeStringToDateTime($net_twitter_status->{created_at}),
        'bb_score' => 0,
            }, $class;
}

sub setScore {
    my ($self, $score) = @_;
    return ($self->{bb_score} = $score);
}

sub getScore {
    my $self = shift;
    return $self->{bb_score};
}

sub getID {
    my $self = shift;
    return 'Twitter' . $self->{nt_status}->{id};
}

sub getText {
    my $self = shift;
    return $self->{nt_status}->{text};
}

sub getDateTime {
    my $self = shift;
    return $self->{bb_datetime};
}

sub getSourceName {
    my $self = shift;
    return $self->{nt_status}->{user}->{screen_name};
}

sub getSourceNameAlt {
    my $self = shift;
    return $self->{nt_status}->{user}->{name};
}

sub getIconURL {
    my $self = shift;
    return $self->{nt_status}->{user}->{profile_image_url};
}

sub getReplyToName {
    my $self = shift;
    return $self->{nt_status}->{in_reply_to_screen_name};
}

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


1;


