package App::BusyBird::Filters;
use strict;
use warnings;

1;

=pod

=head1 NAME

App::BusyBird::Filters - some status filters you might find useful

=head1 EXPORTABLE FUNCTIONS

=head2 ($filter, 0) = filter_exec(@args)

Synchronous filter.

=head2 ($filter, 1) = filter_exec_anyevent(@args)

=head2 ($filter, 0) = filter_user_levels(%level_spec)

=head2 ($filter, 1) = filter_only_new($timeline)

Be sure C<weaken> the C<$timeline>!!

=head2 ($filter, 0) = filter_distribute_to(@timelines)

Be sure C<weakn> the C<@timelines>!!

=cut

