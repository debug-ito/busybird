package App::BusyBird::Log;

use strict;
use warnings;

use base ('Exporter');

use strict;
use warnings;

our @EXPORT_OK = qw(bblog);

sub bblog {
    my ($level, $msg) = @_;
    print STDERR ("$level: $msg\n");
}


1;

