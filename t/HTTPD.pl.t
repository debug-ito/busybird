#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('Getopt::Long');
    use_ok('FindBin');
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('BusyBird::HTTPD');
}
ok(chdir($FindBin::Bin . '/../'), "change the current directory to the base");

my $OPT_WAITTIME = 5;

GetOptions(
    'w=i' => \$OPT_WAITTIME,
);

sub testExtractFormat {
    my ($orig, $pathbody, $format) = @_;
    my ($got_pathbody, $got_format) = BusyBird::HTTPD::_extractFormat(undef, $orig);
    is($got_pathbody, $pathbody, "extracted path body");
    is($got_format, $format, "extracted format");
}

my $cv = AnyEvent->condvar;

if($OPT_WAITTIME > 0) {
    note("Wait for $OPT_WAITTIME seconds.");
    my $tw; $tw = AnyEvent->timer(
        after => $OPT_WAITTIME,
        cb => sub {
            undef $tw;
            $cv->send();
        }
    );
}else {
    note('Wait indefinitely.');
}

BusyBird::HTTPD->init();
BusyBird::HTTPD->start();
{
    note('------ test format extraction');
    foreach my $testcase (
        [qw(/usr/lib/src/main.c /usr/lib/src/main c)],
        [qw(/hoge/compressed.tar.gz /hoge/compressed tar.gz)],
        [qw(/top /top ), ""],
        [qw(/etc/logrotate.d/rsyslog /etc/logrotate.d/rsyslog), ""],
        [qw(/etc/cron.daily/job.sh /etc/cron.daily/job sh)]
    ) {
        &testExtractFormat(@$testcase);
    }
}


$cv->recv();

done_testing();

