package BusyBird::Input::Test;
use base ('BusyBird::Input');
use strict;
use warnings;

use DateTime;
use BusyBird::Status::Test;

my $LOCAL_TZ = DateTime::TimeZone->new( name => 'local' );

sub _getStatuses {
    my ($self, $count, $page) = @_;
    my @ret = ();
    if($page > 0) {
        return undef;
    }
    my $nowtime = DateTime->now();
    $nowtime->set_time_zone($LOCAL_TZ);
    push(@ret, BusyBird::Status::Test->new(
             'ID'   => 'Test' . $nowtime->epoch,
             'Text' => 'Now ' . $nowtime->strftime('%Y/%m/%d %H:%M:%S') . '!!',
             'DateTime' => $nowtime,
             'SourceName'    => 'Test',
             'SourceNameAlt' => 'Te st',
             'IconURL' => '',
             'ReplyToName' => '',
         ));
    return \@ret;
}

1;
