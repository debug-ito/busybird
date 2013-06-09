package BusyBird::StatusStorage::SQLite;
use strict;
use warnings;
use base ("BusyBird::StatusStorage");
use BusyBird::Version;
our $VERSION = $BusyBird::Version::VERSION;

1;

__END__

=pod

=head1 NAME

BusyBird::StatusStorage::SQLite - status storage in SQLite database

=head1 SYNOPSIS

    write synopsis!!

=head1 DESCRIPTION

This is an implementation of L<BusyBird::StatusStorage> interface.
It stores statuses in an SQLite database.

This storage is synchronous, i.e., all operations block the thread.

=head1 CLASS METHOD

=head2 $storage = BusyBird::StatusStorage::SQLite->new(%args)

The constructor.

Fields in C<%args> are:

=over

=item C<path> => FILE_PATH (mandatory)

Path string to the SQLite database file.
If C<":memory:"> is given to this parameter, a temporary in-memory database is created.

=item C<max_status_num> => INT (optional, default: 4096)

The maximum number of statuses the storage can store per timeline.
You cannot expect a timeline to keep more statuses than this number.

=item C<hard_max_status_num> => INT (optional, default: 120% of max_status_num)

The hard limit max number of statuses per timeline.
When the number of statuses in a timeline exceeds this number,
it deletes old statuses from the timeline so that the timeline has C<max_status_num> statuses.

=back

=head1 OBJECT METHODS

L<BusyBird::StatusStorage::SQLite> implements all object methods in L<BusyBird::StatusStorage>.

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut

