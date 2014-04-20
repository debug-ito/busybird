package BusyBird::Filter::Misc;
use strict;
use warnings;
use BusyBird::Version;
our $VERSION = $BusyBird::Version::VERSION;


1;

=pod

=head1 NAME

BusyBird::Filter::Misc - some status filters you might find useful

=head1 EXPORTABLE FUNCTIONS

You can explicitly import all functions below. None of them is exported by default.

=head2 $filter = filter_user_levels(%level_spec)

=head2 ($filter, 1) = filter_only_new($timeline)

Be sure C<weaken> the C<$timeline>!!

=head2 $filter = filter_distribute_to(@timelines)

Be sure C<weaken> the C<@timelines>!!

=cut

