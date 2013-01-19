package App::BusyBird::StatusStorage;

1;

=pod

=head1 NAME

App::BusyBird::StatusStorage - Common interface of Status Storages

=head1 DESCRIPTION

This is a common interface specification of
App::BusyBird::StatusStorage::* module family.


=head1 CLASS METHODS

=head2 $storage = $class->new(@args)

Creates a Status Storage object from C<@args>.

Specification of C<@args> is up to implementations.


=head1 OBJECT METHODS

=head2 $storage->get_statuses(%args)

Fetches statuses from the storage.  The fetched statuses are given to
the C<callback> function.  The operation does not have to be
asynchronous, but C<callback> must be called upon completion.

Fields in C<%args> are as follows.

=over

=item C<timeline> => TIMELINE_NAME (mandatory)

Specifies the name of timeline from which the statuses are fetched.

=item C<callback> => CODEREF($arrayref_of_statuses, $error) (mandatory)

Specifies a subroutine reference that is called upon completion of
fetching statuses.

In success, C<callback> is called with one argument
(C<$arrayref_of_statuses>), which is an array-ref of fetched status
objects.  The array-ref can be empty.

In failure, C<callback> is called with two arguments. The first
argument can be any value. The second argument (C<$error>) is a
defined scalar describing the error.


=item C<ack_state> => {'any', 'unacked', 'acked'} (optional, default: 'any')

Specifies the acked/unacked state of the statuses.

By setting it to C<'unacked'>, this method returns only
unacked statuses from the storage. By setting it to
C<'acked'>, it returns only acked statuses.  By setting it to
C<'any'>, it returns both acked and unacked statuses.


=item C<max_id> => STATUS_ID (optional, default: C<undef>)

Specifies the latest ID of the statuses to be fetched.  It fetches
statues with IDs older than or equal to the specified C<max_id>.  See
L</"Order of Statuses"> for detail.

If there is no such status that has the ID equal to C<max_id> in
specified C<ack_state>, this method returns empty array-ref.

If this option is omitted or set to C<undef>, statuses starting from
the latest status are fetched.


=item C<count> => {'all', NUMBER} (optional)

Specifies the maximum number of statuses to be fetched.

If C<'all'> is specified, all statuses starting from C<max_id> in
specified C<ack_state> are fetched.

The default value of this option is up to implementations.

=back


=head2 $storage->ack_statuses(%args)

Acknowledges a timeline, that is, changing 'unacked' statuses into 'acked'.

Acked status is a status whose C<< $status->{busybird}{acked_at} >> field evaluates to true.
Otherwise, the status is unacked.

Fields in C<%args> are as follows.

=over

=item C<timeline> => TIMELINE_NAME (mandatory)

Specifies the name of timeline.

=item C<ids> => {C<undef>, ID, ARRAYREF_OF_IDS} (optional, default: C<undef>)

Specifies the IDs of statuses to be acked.

If it is a defined scalar, the status with that ID is acked.  If
it is an array-ref of IDs, the statuses with those IDs are acked.
If it is C<undef> or not specified, all unacked statuses in
C<timeline> are acked.

If there is no status with the specified ID in the C<timeline>, it is
ignored.

=item C<callback> => CODEREF($acked_count, $error) (optional, default: C<undef>)

Specifies a subroutine reference that is called when the operation
completes.

In success, the C<callback> is called with one argument
(C<$acked_count>), which is the number of acked statuses.

In failure, the C<callback> is called with two arguments,
and the second one (C<$error>) describes the error.


=back



=head2 $storage->put_statuses(%args)

Inserts statuses to a timeline or updates statuses in a timeline.

Fields in C<%args> are as follows.

=over

=item C<timeline> => TIMELINE_NAME (mandatory)

Specifies the name of timeline where statuses are inserted or updated.

=item C<mode> => {'insert', 'update', 'upsert'} (mandatory)

Specifies the mode of operation.

If C<mode> is C<"insert">, the statuses are inserted (added) to the
C<timeline>.  If C<mode> is C<"update">, the statuses in the
C<timeline> are updated to the give statuses.  If C<mode> is
C<"upsert">, statuses already in the C<timeline> are updated while
statuses not in the C<timeline> are inserted.

The statuses are identified by C<< $status->{id} >> field.  The
C<< $status->{id} >> field must be unique in the C<timeline>.
So if C<mode> is C<"insert">, statuses whose ID is already in the C<timeline>
are ignored and not inserted.


=item C<statuses> => {STATUS, ARRAYREF_OF_STATUSES} (mandatory)

The statuses to be saved in the storage.  It is either a status object
or an array-ref of status objects.

See L<App::BusyBird::Status> for specification of status objects.


=item C<callback> => CODEREF($num_of_statuses, $error) (optional, default: C<undef>)

Specifies a subroutine reference that is called when the operation completes.

In success, C<callback> is called with one argument (C<$num_of_statuses>),
which is the number of statuses inserted or updated.

In failure, C<callback> is called with two arguments,
and the second argument (C<$error>) describes the error.


=back

=head2 $storage->delete_statuses(%args)

Deletes statuses from a timeline.

Fields in C<%args> are as follows.

=over

=item C<timeline> => TIMELINE_NAME (mandatory)

Specifies the name of timeline from which statuses are deleted.

=item C<ids> => {C<undef>, ID, ARRAYREF_OF_IDS} (optional, default: C<undef>)

Specifies the IDs (value of C<< $status->{id} >> field) of the
statuses to be deleted.

If it is a defined scalar, the status with the specified ID is
deleted.  If it is an array-ref of IDs, the statuses with those IDs
are deleted.  If it is C<undef> or not specified, all statuses in the
C<timeline> are deleted.


=item C<callback> => CODEREF($num_of_deletions, $error) (optional, default: C<undef>)

Specifies a subroutine reference that is called when the operation completes.

In success, the C<callback> is called with one argument (C<$num_of_deletions>),
which is the number of deleted statuses.

In failure, the C<callback> is called with two arguments,
and the second argument (C<$error>) describes the error.


=back

=head2 %unacked_counts = $storage->get_unacked_counts(%args)

Returns numbers of unacked statuses in a timeline.

This method operates synchronously and should be fast enough to
deliver real-time updates to the BusyBird users.

Fields in C<%args> are as follows.

=over

=item C<timeline> => TIMELINE_NAME (mandatory)

Specifies the name of timeline.

=back

In success, this method returns a hash (C<%unacked_counts>) describing numbers
of unacked statuses in each level.

Fields in C<%unacked_counts> are as follows.

=over

=item LEVEL => COUNT_OF_UNACKED_STATUSES_IN_THE_LEVEL

Integer keys represent levels. The values is the number of
unacked statueses in the level.

=item C<total> => COUNT_OF_ALL_UNACKED_STATUSES

The key C<"total"> represents the total number of unacked statuses
in the timeline.

=back

In failure, this method throws an exception describing the error.


=head1 GUIDELINE

This section describes guideline of the interface.

Implementations are recommended to follow the guideline, but they are
allowed not to follow it if their own rule is clearly documented.


=head2 Error Handling for Callback-style Methods

=over

=item 1.

Throw an exception if obviously illegal arguments are given, i.e. if
the user is to blame.

=item 2.

Never throw an exception but call C<callback> with C<$error> if you
fail to complete the request, i.e. if you is to blame.

=back


=head2 acked_at Field

C<ack_statuses()> method should update C<< $status->{busybird}{acked_at} >> field
of the target statuses to the date/time string of the current time.
The date/fime format should be the same as C<< $status->{created_at} >> field.


=head2 Order of Statuses

In timelines, statuses are sorted in descending order of
C<< $status->{busybird}{acked_at} >> field
(interpreted as date/time).
Unacked statuses are always above acked statuses.
Ties are broken by sorting the statuses
in descending order of C<< $status->{created_at} >>
field (interpreted as date/time).

So the top of timeline is the latest created unacked status.
Below unacked statuses are layers of acked statuses.
The top of the acked statuses is the latest created status in the latest
acked ones.


=head1 AUTHOR

Toshio Ito

=cut

