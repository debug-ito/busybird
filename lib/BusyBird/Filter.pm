package BusyBird::Filter;
use strict;
use warnings;
use Exporter qw(import);
use Carp;
use Storable qw(dclone);

our @EXPORT = our @EXPORT_OK = qw(filter_map filter_each);
our %EXPORT_TAGS = (all => \@EXPORT_OK);

sub filter_each {
    my ($func) = @_;
    croak "func parameter is mandatory" if not defined $func;
    croak "func parameter must be a code-ref" if ref($func) ne "CODE";
    return sub {
        my $statuses = shift;
        $func->($_) foreach @$statuses;
        return $statuses;
    };
}

sub filter_map {
    my ($func) = @_;
    croak "func parameter is mandatory" if not defined $func;
    croak "func parameter must be a code-ref" if ref($func) ne "CODE";
    return sub {
        my $statuses = shift;
        return [ map { $func->(dclone($_)) } @$statuses ];
    };
}


1;
__END__

=pod

=head1 NAME

BusyBird::Filter - common utilities about status filters

=head1 SYNOPSIS

    use BusyBird;
    use BusyBird::Filter qw(:all);
    
    my $drop_low_level = filter_map sub {
        my $status = shift;
        return $status->{busybird}{level} > 5 ? ($status) : ();
    };
    
    my $set_level = filter_each sub {
        my $status = shift;
        $status->{busybird}{level} = 10;
    };
    
    timeline("home")->add_filter($drop_low_level);
    timeline("home")->add_filter($set_level);

=head1 DESCRIPTION

This module provides some functions to create status filters.

A status filter is a subroutine reference to process an array-ref of statuses.
See L<BusyBird::Timeline>'s C<add_filter()> method for details about status filters.

=head2 Pre-defined Filters

=over

=item L<BusyBird::Filter::Twitter>

Filters and transformations useful when you import statuses from Twitter.

=back

=head1 EXPORTABLE FUNCTIONS

You can import any of the functions below. None of them is exported by default.
Import C<":all"> to import all functions at once.

=head2 $filter = filter_each($func)

Creates a synchronous status filter that modifies each of the statuses destructively.

C<$func> is a subroutine reference that takes a single status.
For each status, C<$func> is called like

    $func->($status)

C<$func> is supposed to modify the given C<$status> destructively.
The result of the C<$filter> is the list of modified statuses.

Return value from C<$func> is ignored.

=head2 $filter = filter_map($func)

Creates a synchronous status filter that maps each of the statuses.
This is similar to Perl's built-in C<map()> function.

C<$func> is a subroutine reference that takes a single status.
For each status, C<$func> is called like

    @mapped_statuses = $func->($status)

C<$func> is supposed to return a list of statuses.
The result of the C<$filter> is all statuses collected from the C<$func>.

Note that the C<$status> given to C<$func> is a deep clone of the original status.
Even if you modify C<$status> in C<$func>, the original status is intact.

=head1 SEE ALSO

=over

=item *

L<BusyBird::Status>

=item *

L<BusyBird::Timeline>

=back

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut
