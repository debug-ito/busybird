package BusyBird::Test;
use base ('Exporter');
use strict;
use warnings;

use Test::More;
use AnyEvent;

our @EXPORT_OK = qw(CV within);

my $cv = AnyEvent->condvar;

sub CV {
    return $cv;
}

sub within {
    my ($timeout, $coderef) = @_;
    $cv = AnyEvent->condvar;
    $cv->begin();
    my $tw; $tw = AnyEvent->timer(
        after => $timeout,
        cb => sub {
            undef $tw;
            fail('Takes too long time. Abort.');
            $cv->send();
        }
    );
    $coderef->();
    $cv->end();
    $cv->recv();
    undef $tw;
}

1;
