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

our $VERSION = '0.01';

1;

=pod

=head1 NAME

App::BusyBird::Log - logger singleton in App::BusyBird

=head1 VERSION

0.01

=head1 SYNOPSIS

    use App::BusyBird::Log;
    
    App::BusyBird::Log->logger->(sub {
        my ($level, $msg) = @_;
        print STDERR ("$level: $msg\n");
    });


=head1 DESCRIPTION

L<App::BusyBird::Log> stores the logger singleton object.
The object is used as the default logger throughout various components in L<App::BusyBird>.

=head1 CLASS METHODS

=head2 $logger = App::BusyBird::Log->logger([$logger])

Accessor for the logger singleton.

The logger object is just a subroutine reference that takes two arguments: C<$level> and C<$msg>.
C<$level> is a string of log level such as 'info', 'warn', 'error', 'critical' etc.
C<$msg> is the log message body.

=head1 AUTHOR

Toshio Ito C<< toshioito [at] cpan.org >>

=cut

