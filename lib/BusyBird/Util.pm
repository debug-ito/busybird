package BusyBird::Util;
use strict;
use warnings;
use Scalar::Util ('blessed');
use Carp;
use DateTime;
use base ('Exporter');

my @DATETIME_NAMES = qw(datetimeFormat datetimeParse datetimeNormalize $SYSTEM_TIMEZONE);

our @EXPORT_OK = (qw(setParam expandParam), @DATETIME_NAMES);
our %EXPORT_TAGS = (
    datetime => [@DATETIME_NAMES],
);
our $SYSTEM_TIMEZONE = DateTime::TimeZone->new( name => 'local');


###

my @MONTH = (undef, qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec));
my %MONTH_FROM_STR = ( map { $MONTH[$_] => $_ } 1..12);
my @DAY_OF_WEEK = (undef, qw(Mon Tue Wed Thu Fri Sat Sun));

my $DATETIME_MATCHER_STANDARD;
my $DATETIME_MATCHER_SEARCH;
my $DATETIME_MATCHER_NUMERIC = qr!(\d{4})[\-/](\d{1,2})[\-/](\d{1,2})[ T]+(\d{2}):(\d{2}):(\d{2})(\.\d{1,3})?([\+\-]\d{2}:?\d{2})?!;
{
    my $month_selector = join('|', @MONTH[1..12]);
    my $dow_selector = join('|', @DAY_OF_WEEK[1..7]);
    $DATETIME_MATCHER_STANDARD = qr!($dow_selector)[, ]+($month_selector)[, ]+(\d{2})[, ]+(\d{2}):(\d{2}):(\d{2})[, ]+([\-\+]\d{4})[, ]+(\d+)!;
    $DATETIME_MATCHER_SEARCH = qr!($dow_selector)[, ]+(\d{2})[, ]+($month_selector)[, ]+(\d{4})[, ]+(\d{2}):(\d{2}):(\d{2})[, ]+([\-\+]\d{4})!;
}

### 

sub setParam {
    my ($hashref, $params_ref, $key, $default, $is_mandatory) = @_;
    if($is_mandatory && !defined($params_ref->{$key})) {
        my $classname = blessed $hashref;
        croak "ERROR: setParam in $classname: Parameter for '$key' is mandatory, but not supplied.";
    }
    $hashref->{$key} = (defined($params_ref->{$key}) ? $params_ref->{$key} : $default);
}

sub expandParam {
    my ($param, @names) = @_;
    my $refparam = ref($param);
    my @result = ();
    if($refparam eq 'ARRAY') {
        @result = @$param;
    }elsif($refparam eq 'HASH') {
        @result = @{$param}{@names};
    }else {
        $result[0] = $param;
    }
    return wantarray ? @result : $result[0];
}

sub datetimeFormat {
    my ($dt, $set_timezone) = @_;
    return undef if !defined($dt);
    if(defined($SYSTEM_TIMEZONE) && $set_timezone) {
        $dt = $dt->clone();
        $dt->set_time_zone($SYSTEM_TIMEZONE);
    }
    return sprintf("%s %s %s",
                   $DAY_OF_WEEK[$dt->day_of_week],
                   $MONTH[$dt->month],
                   $dt->strftime('%d %H:%M:%S %z %Y'));
}

sub datetimeParse {
    my ($dt_str, $set_timezone) = @_;
    my $dt = undef;
    my ($dow, $month_str, $dom, $h, $m, $s, $tz_str, $year) = ($dt_str =~ $DATETIME_MATCHER_STANDARD);
    if(!$dow) {
        ($dow, $dom, $month_str, $year, $h, $m, $s, $tz_str) = ($dt_str =~ $DATETIME_MATCHER_SEARCH);
    }
    if($dow) {
        $dt = DateTime->new(
            year      => $year,
            month     => $MONTH_FROM_STR{$month_str},
            day       => $dom,
            hour      => $h,
            minute    => $m,
            second    => $s,
            time_zone => $tz_str,
        );
    }
    if(!defined($dt)) {
        my ($month_num, $millisec_num);
        ($year, $month_num, $dom, $h, $m, $s, $millisec_num, $tz_str) = ($dt_str =~ $DATETIME_MATCHER_NUMERIC);
        $dt = DateTime->new(
            year   => $year,
            month  => $month_num,
            day    => $dom,
            hour   => $h,
            minute => $m,
            second => $s,
        );
        if(defined($tz_str)) {
            $tz_str =~ s/://g;
            $dt->set_time_zone($tz_str);
        }
    }
    if($set_timezone && defined($SYSTEM_TIMEZONE) && defined($dt)) {
        $dt->set_time_zone($SYSTEM_TIMEZONE);
    }
    return $dt;
}

sub datetimeNormalize {
    my ($dt_str, $set_timezone) = @_;
    return datetimeFormat(datetimeParse($dt_str, $set_timezone));
}


1;
