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

=head2 $need_help = run(@argv)

Runs the L<BusyBird> process instance.

C<@argv> is the command-line arguments. See L<busybird> for detail.

Return value C<$need_help> indicates if the user might need some help.
If C<@argv> has no problem, C<$need_help> is C<undef>.
If C<@argv> has some problem, C<$need_help> is a string explaining what's wrong.
If help is requested in C<@argv>, C<$need_help> is an empty string.

=head1 AUTHOR

Toshio Ito C<< toshioito [at] cpan.org >>

=cut

