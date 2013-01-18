package App::BusyBird::Log;
use strict;
use warnings;

use Exporter qw(import);

use strict;
use warnings;

my $logger = \&default_logger;

sub default_logger {
    my ($level, $msg) = @_;
    print STDERR ("$level: $msg\n");
}

sub logger {
    my ($class, $in_logger) = @_;
    if(@_ > 1) {
        $logger = $in_logger || \&default_logger;
    }
    return $logger;
}

1;

