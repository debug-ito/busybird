package App::BusyBird::Timeline;
use strict;
use warnings;

1;

=pod

=head1 NAME

App::BusyBird::Timeline - a timeline object in BusyBird

=head1 DESCRIPTION

=head2 Filter

=head2 Updates Watcher


=head1 CLASS METHODS

=head1 OBJECT METHODS

=head2 $name = $timeline->name()

=head2 $timeline->add_statuses($arrayref_of_statuses, [$callback->($added_num, $error)])

=head2 $timeline->ack_statuses($max_id, [$callback->($acked_num, $error)])

=head2 $timeline->get_statuses(%options, $callback->($arrayref_of_statuses, $error))

=over

=item C<max_id>

=item C<count>

=item C<ack_state>

=back

=head2 %unacked_counts = $timeline->unacked_counts()


=head2 $timeline->contains($arrayref_of_ids, $callback->($contained_ids, $not_contained_ids, $error))


=head2 $watcher = $timeline->watch_updates(%watch_spec, $callback->($w, %updates))

Where should I write the specification of updates?

=head2 $timeline->add_filter($filter->($statuses))

Returning C<undef> from C<$filter> means no change is done to C<$statuses>.

=head2 $timeline->add_filter_async($filter->($statuses, $done))


=head2 $storage = $timeline->status_storage()

=head1 AUTHOR

Toshio Ito C<< toshioito [at] cpan.org >>

=cut
