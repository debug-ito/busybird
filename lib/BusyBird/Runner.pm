package BusyBird::Runner;
use strict;
use warnings;

1;
__END__

=pod

=head1 NAME

BusyBird::Runner - BusyBird process runner

=head1 SYNOPSIS

    #!/usr/bin/perl
    use strict;
    use warnings;
    use BusyBird::Runner qw(run);
    
    run(@ARGV);

=head1 DESCRIPTION

L<BusyBird::Runner> runs L<BusyBird> process instance.
This is the direct back-end of C<busybird> command.

=head1 EXPORTABLE FUNCTIONS

The following functions are exported only by request.

=head2 run(@argv)

Runs the L<BusyBird> process instance.

C<@argv> is the command-line arguments. See L<busybird> for detail.

=head1 AUTHOR

Toshio Ito C<< toshioito [at] cpan.org >>

=cut

