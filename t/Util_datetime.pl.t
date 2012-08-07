
use DateTime;
use Test::More;

BEGIN {
    use_ok('BusyBird::Util', qw(:datetime));
}

sub DT {
    my ($year, $month, $day, $hour, $minute, $second, $time_zone) = @_;
    return DateTime->new(
        year => $year,
        month => $month,
        day => $day,
        hour => $hour,
        minute => $minute,
        second => $second,
        time_zone => $time_zone,
    );
}

sub checkParse {
    my ($str, $set_timezone, $exp_dt) = @_;
    my $got_dt = datetimeParse($str, $set_timezone);
    cmp_ok(DateTime->compare($got_dt, $exp_dt), '==', 0, "parsed to $exp_dt");
    if($set_timezone) {
        ok($got_dt->time_zone->is_utc(), "timezone is converted to UTC");
    }else {
        ok(!$got_dt->time_zone->is_utc(), "timezone remains non-UTC");
    }
}

sub checkFormat {
    my ($dt, $set_timezone, $exp_str) = @_;
    my $got_str = datetimeFormat($dt, $set_timezone);
    is($got_str, $exp_str, "format to $exp_str");
}

$SYSTEM_TIMEZONE = DateTime::TimeZone->new(name => 'UTC');

checkParse "Fri Jul 16 16:58:46 +0200 2010", 0, DT qw(2010 7 16 14 58 46 +0000);
checkParse "some text here. Wed  Feb  29 23:34:06 +0900  2012", 0, DT qw(2012 2 29 14 34 6 +0000);
checkParse "Mon, 23 Oct 2011  19:03:12 -0500" ,1, DT qw(2011 10 24 0 3 12 +0000);
checkParse "2012-09-23T11:00:10+08:00", 1, DT qw(2012 9 23 3 0 10 +0000);
checkParse "2011/07/12 04:02:00-1030", 0, DT qw(2011 7 12 14 32 0 +0000);

checkFormat DT(qw(2010 8 22 3 34 0 +0900)), 0, "Sun Aug 22 03:34:00 +0900 2010";
checkFormat DT(qw(2012 1 1 15 8 45 +2000)), 1, "Sat Dec 31 19:08:45 +0000 2011";


done_testing();


