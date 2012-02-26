package BusyBird::Log;
use base ('Exporter');

use strict;
use warnings;

our @EXPORT_OK = qw(bblog);

sub bblog {
    my ($msg) = @_;
    print STDERR ($msg . "\n");
}


1;

