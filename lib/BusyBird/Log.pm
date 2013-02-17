package BusyBird::Log;
use strict;
use warnings;

use Exporter qw(import);

use strict;
use warnings;

our @EXPORT = qw(bblog);
our @EXPORT_OK = @EXPORT;
our $LOGGER = \&default_logger;

sub default_logger {
    my ($level, $msg) = @_;
    my ($caller_package) = caller(1);
    print STDERR ("$caller_package: $level: $msg\n");
}

sub bblog {
    my ($level, $msg) = @_;
    $LOGGER->($level, $msg) if defined $LOGGER;
}

our $VERSION = '0.01';

1;

=pod

=head1 NAME

BusyBird::Log - simple logging infrastructure for BusyBird

=head1 VERSION

0.01

=head1 SYNOPSIS


    use BusyBird::Log;
    
    bblog('error', 'Something bad happens');
    
    {
        my @logs = ();
        
        ## Temporarily change the LOGGER
        local $BusyBird::Log::LOGGER = sub {
            my ($level, $msg) = @_;
            push(@logs, [$level, $msg]);
        };

        bblog('info', 'This goes to @logs array.');
    }


=head1 DESCRIPTION

L<BusyBird::Log> manages the logger singleton used in L<BusyBird>.
By default, C<bblog()> function of L<BusyBird::Log> prints the log to STDERR.


=head1 EXPORTED FUNCTIONS

=head2 bblog($level, $msg)

C<bblog()> function is exported by default.
This function logs the given message.

C<$level> is a string of log level such as 'info', 'warn', 'error', 'critical' etc.
C<$msg> is the log message body.


=head1 PACKAGE VARIABLES

=head2 $BusyBird::Log::LOGGER = CODEREF($level, $msg)

A subroutine reference that is called when C<bblog()> is called.
The subroutine is supposed to do the logging.

Setting this to C<undef> disables logging at all.



=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut

