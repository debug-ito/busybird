package BusyBird::Stream;

## OBSOLETE: これはもう使わないと思う。

use strict;
use warnings;
use Net::Twitter;
use Scalar::Util 'blessed';
use DateTime;
use Encode;

## my $CONSUMER_KEY = 'yATsFfj4h1twqSZ1fTZg';
## my $CONSUMER_SECRET = 'ACagmKXK7fVGnMHmDcKxInz3mv2yGpAeAvbyPVDkMno';
## my $TOKEN = '106098831-F8HhdA5ACP9GIIaA223GJ3Dm9ojJujFX8c4cycq6';
## my $TOKEN_SECRET = 'eZxehkiVgdFCe3AjcToNRFSQ79BqQq3E1BuZEC08xDE';
my %MONTH = (
    Jan => 1, Feb => 2,  Mar =>  3, Apr =>  4,
    May => 5, Jun => 6,  Jul =>  7, Aug =>  8,
    Sep => 9, Oct => 10, Nov => 11, Dec => 12,
    );
my $PAGE_COUNT = 20;
my $PAGE_MAX   = 1;

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

sub new() {
    my ($class, $consumer_key, $consumer_secret, $token, $token_secret) = @_;
    my $self = {
        'nt' => Net::Twitter->new(
            traits   => [qw/OAuth API::REST/],
            consumer_key        => $consumer_key,
            consumer_secret     => $consumer_secret,
            access_token        => $token,
            access_token_secret => $token_secret,
            ssl => 1,
            ),
            'timelines' => [],
    };
    return bless $self, $class;
}

sub addHomeTimeLine() {
    my ($self) = @_;
    $self->_addTimeLine(
        'home_timeline',
        sub {
            my ($nt, $count, $page) = @_;
            return $nt->home_timeline(count => $count, page => $page);
        }
        );
}

sub _addTimeLine() {
    my ($self, $name, $tl_getter_func) = @_;
    push($self->{timelines}, {'name' => $name, 'getTL' => $tl_getter_func, 'is_complete' => 0});
}

sub _isAllTimeLinesComplete() {
    my ($self) = @_;
    foreach my $tl (@{$self->{timelines}}) {
        return 0 if !$tl->{is_complete};
    }
    return 1;
}

sub _resetTimeLineCompleteness() {
    my ($self) = @_;
    foreach my $tl (@{$self->{timelines}}) {
        $tl->{is_complete} = 0;
    }
}

sub _getStream() {
    my ($self, $page, $threshold_epoch_time) = @_;
    my $ret_statuses = [];
    foreach my $tl (@{$self->{timelines}}) {
        next if $tl->{is_complete};
        $tl->{is_complete} = 1;
        my $statuses = &{$tl->{getTL}}($self->{nt}, $PAGE_COUNT, $page);
        foreach my $status ( @$statuses ) {
            print STDERR (encode('utf8', "GET> $status->{created_at} <$status->{user}{screen_name}> $status->{text}\n"));
            my $datetime = &_timeStringToDateTime($status->{created_at});
            if($datetime->epoch >= $threshold_epoch_time) {
                $status->{bb_create_at_datetime} = $datetime;
                $status->{bb_timeline} = $tl->{name};
                unshift(@$ret_statuses, $status);
                $tl->{is_complete} = 0;
            }
        }
    }
    return $ret_statuses;
}

sub getNewStatuses() {
    my ($self, $threshold_epoch_time) = @_;
    my $ret_array = [];
    $self->_resetTimeLineCompleteness();
    for(my $page = 0 ; $page < $PAGE_MAX ; $page++) {
        eval {
            my $statuses = $self->getStream($page);
            push(@$ret_array, @$statuses);
            if($self->_isAllTimeLinesComplete()) {
                return $ret_array;
            }
        };
        if ( my $err = $@ ) {
            die $@ unless blessed $err && $err->isa('Net::Twitter::Error');
            die "HTTP Response Code: ", $err->code, "\n",
            "HTTP Message......: ", $err->message, "\n",
            "Twitter error.....: ", $err->error, "\n";
        }
    }
    print STDERR ("WARNING: page has reached the max value of $PAGE_MAX\n");
    return $ret_array;
}

## home_timeline
##     Parameters: since_id, max_id, count, page, skip_user, exclude_replies, contributor_details, include_rts, include_entities, trim_user, include_my_retweet
##     Required: none
##     Returns the 20 most recent statuses, including retweets, posted by the authenticating user and that user's friends. This is the equivalent of /timeline/home on the Web.
##     Returns: ArrayRef[Status]

1;
