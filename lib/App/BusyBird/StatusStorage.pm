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

=head2 $storage->fetch_statuses_async(%query, $callback->($arrayref_of_statuses, $error))

Fetches statuses from the storage.
The fetched statuses are given to the C<$callback> function.
The operation does not have to be asynchronous, but C<$callback> must be called
in completion.

In C<%query>, the caller can specify the following query options.

=over

=item C<timeline> => TIMELINE_NAME (mandatory)

Specifies the name of timeline from which the statuses are fetched.


=item C<type> => {'all', 'new', 'old'} (optional, default: 'all')

Specifies the type of statuses.

By setting it to C<'new'>, this method returns only new (unconfirmed) statuses
from the storage. By setting it to C<'old'>, it returns only old (confirmed) statuses.
By setting it to C<'all'>, it returns both new and old statuses.


=item C<max_id> => STATUS_ID (optional, default: C<undef>)

Specifies the latest ID of the statuses to be fetched.
It fetches statues with IDs older than or equal to the specified C<max_id>.

If there is no such status that has the ID equal to C<max_id> in specified C<type>,
this method returns empty array-ref.

If this option is omitted or set to C<undef>, statuses starting from the latest status
are fetched.


=item C<count> => {'all', NUMBER} (optional)

Specifies the maximum number of statuses to be fetched.

If C<'all'> is specified, all statuses starting from C<max_id> in specified C<type> are fetched.

The default value of this option is up to implementations.

=back

C<$callback> is a subroutine reference that is called in completion of fetching statuses.

In success, C<$callback> is called with one argument (C<$arrayref_of_statuses>),
which is an array-ref of fetched status objects.
The array-ref can be empty.

In failure, C<$callback> is called with two arguments.
The second argument (C<$error>) is a defined scalar describing the error.


=head2 $storage->confirm(timeline => $timeline_name)

Confirms the timeline, that is, changing all the 'new' statuses into 'old'.

C<$timeline_name> is the name of timeline whose statuses are confirmed.


=head2 $storage->add_statuses(%args)

Add statuses to a timeline. The added statuses are 'new' until they are confirmed.

C<%args> is composed of:

=over

=item C<timeline> => TIMELINE_NAME (mandatory)

The name of timeline that statuses are added to.


=item C<statuses> => {STATUS, ARRAYREF_OF_STATUSES}

The statuses to be added.
It is either a status object or an array-ref of status objects.


=back


=head1 AUTHOR

Toshio Ito

=cut

