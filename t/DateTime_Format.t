use strict;
use warnings;
use DateTime;
use Test::More;

BEGIN {
    use_ok('App::BusyBird::DateTime::Format');
}

my $formatter = 'App::BusyBird::DateTime::Format';

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
    my ($str, $exp_dt) = @_;
    my $got_dt = $formatter->parse_datetime($str);
    if(defined($exp_dt)) {
        cmp_ok(DateTime->compare($got_dt, $exp_dt), '==', 0, "parsed to $exp_dt");
    }else {
        ok(!defined($got_dt), "expect to fail parsing");
    }
}

sub checkFormat {
    my ($dt, $exp_str) = @_;
    my $got_str = $formatter->format_datetime($dt);
    is($got_str, $exp_str, "format to $exp_str");
}

checkParse "Fri Jul 16 16:58:46 +0200 2010", DT qw(2010 7 16 16 58 46 +0200);
checkParse "Mon Dec 03 00:01:23 +0900 2012", DT qw(2012 12 3 0 1 23 +0900);
checkParse "Thu Jan 03 02:24:43 +0000 2013", DT qw(2013 1 3 2 24 43 +0000);
checkParse "Thu Jan 03 14:44:12 +0900 2013", DT qw(2013 1 3 14 44 12 +0900);
checkParse "some text here. Wed  Feb  29 23:34:06 +0900  2012", undef;
checkParse "Thu, 06 Oct 2011 19:36:17 +0000", DT qw(2011 10 6 19 36 17 +0000);
checkParse "Sun, 23 Oct 2011 19:03:12 -0500", DT qw(2011 10 23 19 3 12 -0500);
checkParse "2012-09-23T11:00:10+0800", undef;
checkParse "2012-09-23T11:00:10+08:00", DT qw(2012 9 23 11 0 10 +0800);
checkParse "2011/07/12 04:02:00-10:30", undef;

checkFormat DT(qw(2010 8 22 3 34 0 +0900)), "Sun Aug 22 03:34:00 +0900 2010";
checkFormat DT(qw(2012 1 1 15 8 45 +2000)), "Sun Jan 01 15:08:45 +2000 2012";


done_testing();
