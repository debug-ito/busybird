package App::BusyBird::Main;
use strict;
use warnings;


our $VERSION = '0.01';

1;

=pod

=head1 NAME

App::BusyBird::Main - main application object of App::BusyBird

=head1 VERSION

0.01

=head1 SYNOPSIS

    Write synopsis!!

=head1 DESCRIPTION

L<App::BusyBird::Main> is the main application object of L<App::BusyBird>.
It keeps application configuration and timelines (L<App::BusyBird::Timeline> objects).

=head1 CLASS METHODS

=head2 $main = App::BusyBird::Main->new()

Creates a L<App::BusyBird::Main> object.

Users usually don't have to call this method.
The singleton instance of L<App::BusyBird::Main> object is created and obtained
by C<busybird()> method from L<App::BusyBird> module.
See L<App::BusyBird::Tutorial> for detail.

=head1 OBJECT METHODS

=head2 $app = $main->to_app()

Creates and returns a L<PSGI> application object from the C<$main> object.

=head2 $timeline = $main->timeline($name)

Returns the C<$timeline> whose name is C<$name> from the C<$main>.
C<$timeline> is a L<App::BusyBird::Timeline> object.

If there is no timeline named C<$name> in C<$main>, a new timeline is created, installed and returned.
C<$name> must be a string consisting only of C<[a-zA-Z0-9_-]>.


=head2 $timeline = $main->get_timeline($name)

Returns the C<$timeline> whose name is C<$name> from the C<$main>.

If there is no timeline named C<$name> in C<$main>, it returns C<undef>.


=head2 @timelines = $main->get_all_timelines()

Returns the list of all timelines installed in the C<$main>.

=head2 $main->install_timeline($timeline)

Installs the given C<$timeline> to the C<$main>.

If a timeline with the same name as the given C<$timeline> is already installed in the C<$main>,
the old timeline is replaced by the given C<$timeline>.

=head2 $timeline = $main->uninstall_timeline($name)

Uninstalls the timeline whose name is C<$name> from the C<$main>.
It returns the uninstalled C<$timeline>.

If there is no timeline named C<$name>, it returns C<undef>.

=head2 $status_storage = $main->default_status_storage([$status_storage])

Accessor for the default StatusStorage object used by C<$main>.

A StatusStorage is an object where timelines save their statuses.
When a timeline is created by C<timeline()> method, the default StatusStorage is used for the timeline.

When an argument is given, this method sets the default StatusStorage to the given C<$status_storage> object.
This method returns the current (changed) default StatusStorage object.

Note that the default StatusStorage object is referred to only when creating timelines via C<timeline()> method.
Existing timelines are not affected by changing the default StatusStorage object.

A StatusStorage object is an object implementing L<App::BusyBird::StatusStorage> interface specification.
For example, the following modules can be used as StatusStorage.

=over

=item *

L<App::BusyBird::StatusStorage::Memory> - storage in the process memory

=back

See each module's documentation for details.


=head2 $main->watch_unacked_counts($level, $watch_spec, $callback->($w, $tl_unacked_counts, $error))

(Not provider $watcher to outside. You should not take C<$w> out of C<$callback>'s scope)


=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut



