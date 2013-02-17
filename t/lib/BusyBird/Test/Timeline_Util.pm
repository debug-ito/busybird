package BusyBird::Test::Timeline_Util;
use strict;
use warnings;
use Exporter qw(import);
use Test::More;
use Test::Builder;
use BusyBird::DateTime::Format;
use DateTime;

## We have to export typeglobs when we want to allow users
## to localize the LOOP and UNLOOP. See 'perlmod' for details.
our @EXPORT_OK = qw(sync status *LOOP *UNLOOP);
our $LOOP   = sub {};
our $UNLOOP = sub {};

sub sync {
    my ($timeline, $method, %args) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $callbacked = 0;
    my $result;
    $timeline->$method(%args, callback => sub {
        $result = \@_;
        $callbacked = 1;
        $UNLOOP->();
    });
    $LOOP->();
    ok($callbacked, "sync $method callbacked.");
    return @$result;
}

sub status {
    my ($id, $level) = @_;
    my %level_elem = defined($level) ? (busybird => { level => $level }) : ();
    return {
        id => $id,
        created_at => BusyBird::DateTime::Format->format_datetime(
            DateTime->from_epoch(epoch => $id, time_zone => 'UTC')
        ),
        %level_elem
    };
}


1;
