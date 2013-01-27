package App::BusyBird::Timeline;
use strict;
use warnings;

our $VERSION = '0.01';

1;

=pod

=head1 NAME

App::BusyBird::Timeline - a timeline object in BusyBird

=head1 VERSION

0.01

=head1 SYNOPSIS

=head1 DESCRIPTION

=head2 Filter

=head1 CLASS METHODS

=head2 $timeline = App::BusyBird::Timeline->new(%args)

Creates a new timeline.

You can create a timeline via L<App::BusyBird::Main>'s C<timeline()> method,
but C<new()> method allows for more detailed customization.

Fields in C<%args> are as follows.

=over

=item C<name> => STRING (mandatory)

Specifies the name of the timeline.
It must be a string consisting only of C<[a-zA-Z0-9_-]>.

=item C<storage> => STATUS_STORAGE (mandatory)

Specifies the status storage object that implements the interface documented in L<App::BusyBird::StatusStorage>.
Statuses in C<$timeline> is saved to the C<storage>.

=item C<logger> => CODEREF($level, $msg) (optional, default: C<< App::BusyBird::Log->logger >>)

Specifies the logger subroutine reference.
See L<App::BusyBird::Log> for the spec of the logger.

=back


=head1 OBJECT METHODS

=head2 $name = $timeline->name()

Returns the C<$timeline>'s name.

=head2 $timeline->add_statuses($arrayref_of_statuses, [$callback->($added_num, $error)])

Adds statuses to the C<$timeline>. This is the front-end of C<put_statuses()> method of L<App::BusyBird::StatusStorage>.

C<$arrayref_of_statuses> is an array-ref of status objects. See L<App::BusyBird::Status> about what status objects look like.

Optional parameter C<$callback> is a subroutine reference.
If specified, it is called when the operation has completed.
In success, C<$callback> is called with one argument (C<$added_num>), which is the number of statuses actually added to the C<$timeline>.
In failure, C<$callback> is called with two arguments, and the second argument (C<$error>) describes the error.

Note that statuses added by C<add_statuses()> method go through the C<$timeline>'s filter.
It is the filtered statuses that are actually inserted to the storage.


=head2 $timeline->ack_statuses($max_id, [$callback->($acked_num, $error)])

Acknowledges statuses in the C<$timeline>. This is the front-end of C<ack_statuses()> method of L<App::BusyBird::StatusStorage>.

C<$max_id> is the latest ID of the statuses to be acked.
Unacked statuses with IDs older or equal to C<$max_id> are acked.
If C<$max_id> is C<undef>, all the unacked statuses are acked.

Optional parameter C<$callback> is a subroutine reference.
If specified, it is called when the operation has completed.
In success, C<$callback> is called with one argument (C<$acked_num>), which is the number of statuses acked.
In failure, C<$callback> is called with two arguments, and the second argument (C<$error>) describes the error.


=head2 $timeline->get_statuses(%options, $callback->($arrayref_of_statuses, $error))

Fetches statuses from the C<$timeline>. This is the front-end of C<get_statuses()> method of L<App::BusyBird::StatusStorage>.

The following named options can be specified in C<%options>.
See L<< App::BusyBird::StatusStorage/$storage->get_statuses(%args) >> for specification of the options.

=over

=item *

C<max_id>

=item *

C<count>

=item *

C<ack_state>

=back

Mandatory parameter C<$callback> is a subroutine reference.
In success, C<$callback> is called with one argument (C<$arrayref_of_statuses>), which is an array-ref of fetched statuses.
In failure, C<$callback> is called with two arguments, and the second argument (C<$error>) describes the error.


=head2 %unacked_counts = $timeline->unacked_counts()

Returns number of unacked statuses for each status level.
This is the front-end of C<get_unacked_counts()> method of L<App::BusyBird::StatusStorage>.

See L<< App::BusyBird::StatusStorage/%unacked_counts = $storage->get_unacked_counts(%args) >> for detail about the return value (C<%unacked_count>).

In failure, this method throws an exception.


=head2 $timeline->contains($arrayref_of_statuses_or_ids, $callback->($contained, $not_contained, $error))

Checks whether the given statuses (or IDs) are contained in the C<$timeline>.

C<$arrayref_of_statuses_or_ids> is an array-ref of status objects or status IDs to be checked.
Status objects and IDs can be mixed in a single array-ref.

C<$callback> is a subroutine reference that is called when the check has completed.

In success, C<$callback> is called with two arguments (C<$contained>, C<$not_contained>).
C<$contained> is an array-ref of given statuses or IDs that are contained in the C<$timeline>.
C<$not_contained> is an array-ref of given statuses or IDs that are NOT contained in the C<$timeline>.

In failure, C<$callback> is called with three arguments, and the third argument (C<$error>) describes the error.


=head2 $timeline->add_filter($filter->($arrayref_of_statuses))

Add a status filter to the C<$timeline>.

C<$filter> is a subroutine reference that takes one argument (C<$arrayref_of_statuses>).

C<$arrayref_of_statuses> is an array-ref of statuses that is injected to the filter.
C<$filter> can use and modify the C<$arrayref_of_statuses>.

C<$filter> must return an array-ref of statuses, which is going to be passed to the next filter
(or the status storage if there is no next filter).
The return value of C<$filter> may be either C<$arrayref_of_statuses> or a new array-ref.


=head2 $timeline->add_filter_async($filter->($arrayref_of_statuses, $done))

Add an asynchronous status filter to the C<$timeline>.

C<$filter> is a subroutine reference that takes two arguments (C<$arrayref_of_statuses>, C<$done>).
C<$arrayref_of_statuses> is an array-ref of statuses that is injected to the filter.
C<$done> is a subroutine reference.

Instead of returning the result, C<$filter> must call C<< $done->($result) >> when it completes the filtering task.


=head2 $watcher = $timeline->watch_updates(%watch_spec, $callback->($w, %updates))

TBW...

Where should I write the specification of updates?
Maybe Web API documetion is the right place.

=head2 $storage = $timeline->status_storage()

Returns the status storage object that the C<$timeline> uses.

=head1 AUTHOR

Toshio Ito C<< toshioito [at] cpan.org >>

=cut
