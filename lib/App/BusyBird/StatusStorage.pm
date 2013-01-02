package App::BusyBird::StatusStorage;

1;

=pod

=head1 NAME

App::BusyBird::StatusStorage - Common interface of Status Storages

=head1 DESCRIPTION

This is a common interface specification of
App::BusyBird::StatusStorage::* module family.


=head1 CLASS METHODS

=head2 $storage = $class->new(%options)

Creates a Status Storage object from C<%options>.

Specification of C<%options> is up to implementations.


=head1 OBJECT METHODS

=head2 $storage->get_statuses(%args)

Fetches statuses from the storage.  The fetched statuses are given to
the C<callback> function.  The operation does not have to be
asynchronous, but C<callback> must be called in completion.

Fields in C<%args> are as follows.

=over

=item C<timeline> => TIMELINE_NAME (mandatory)

Specifies the name of timeline from which the statuses are fetched.

=item C<callback> => CODEREF($arrayref_of_statuses, $error) (mandatory)

Specifies a subroutine reference that is called in completion of
fetching statuses.

In success, C<callback> is called with one argument
(C<$arrayref_of_statuses>), which is an array-ref of fetched status
objects.  The array-ref can be empty.

In failure, C<callback> is called with two arguments. The first
argument can be any value. The second argument (C<$error>) is a
defined scalar describing the error.


=item C<read_state> => {'all', 'unread', 'read'} (optional, default: 'all')

Specifies the read/unread state of the statuses.

By setting it to C<'unread'>, this method returns only unread
(unconfirmed) statuses from the storage. By setting it to C<'read'>,
it returns only read (confirmed) statuses.  By setting it to C<'all'>,
it returns both read and unread statuses.


=item C<max_id> => STATUS_ID (optional, default: C<undef>)

Specifies the latest ID of the statuses to be fetched.  It fetches
statues with IDs older than or equal to the specified C<max_id>.

If there is no such status that has the ID equal to C<max_id> in
specified C<read_state>, this method returns empty array-ref.

If this option is omitted or set to C<undef>, statuses starting from
the latest status are fetched.


=item C<count> => {'all', NUMBER} (optional)

Specifies the maximum number of statuses to be fetched.

If C<'all'> is specified, all statuses starting from C<max_id> in
specified C<read_state> are fetched.

The default value of this option is up to implementations.

=back


=head2 $storage->confirm_statuses(%args)

Confirms a timeline, that is, changing 'unread' statuses into 'read'.

Fields in C<%args> are as follows.

=over

=item C<timeline> => TIMELINE_NAME (mandatory)

FROM ARAOUND HERE

=item C<ids> => {C<undef>, ID, ARRAYREF_OF_IDS} (optional, default: C<undef>)

=item C<callback> => CODEREF($result, $error) (optional, default: C<undef>)

=back



=head2 $storage->put_statuses(%args)

Insert statuses to a timeline or update statuses in a timeline.

Fields in C<%args> are as follows.

=over

=item C<timeline> => TIMELINE_NAME (mandatory)

The name of timeline that statuses are added to.

=item C<mode> => {'insert', 'update', 'upsert'} (mandatory)

=item C<statuses> => {STATUS, ARRAYREF_OF_STATUSES} (mandatory)

The statuses to be saved in the storage.  It is either a status object
or an array-ref of status objects.

=item C<callback> => CODEREF($result, $error) (optional, default: C<undef>)

=back

=head2 $storage->delete_statuses(%args)

Fields in C<%args> are as follows.

=over

=item C<timeline> => TIMELINE_NAME (mandatory)

=item C<ids> => {C<undef>, ID, ARRAYREF_OF_IDS} (optional, default: C<undef>)

=item C<callback> => CODEREF($result, $error) (optional, default: C<undef>)

=back

=head2 %unread_counts = $storage->get_unread_counts(%args)

Fields in C<%args> are as follows.

=over

=item C<timeline> => TIMELINE_NAME (mandatory)

=back


=head1 GENERAL RULES

=head2 Error Handling for callback-style methods

=over

=item 1.

Throw an exception if illegal arguments are given, i.e. if the user is
to blame.

=item 2.

Never throw an exception but call C<callback> with C<$error> if you
fail to complete the request, i.e. if you is to blame.

=back

=head2 Order of Statuses


=head1 SPECIFICATION OF STATUS OBJECTS

Is this supposed to be in Timeline.pm or an individual file?

=head2 $status->{id}

=head2 $status->{created_at}

=head2 $status->{busybird}{is_read}

=head2 $status->{busybird}{timeline}

=head2 $status->{busybird}{level}


=head1 AUTHOR

Toshio Ito

=cut

