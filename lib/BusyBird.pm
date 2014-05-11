package BusyBird;
use strict;
use warnings;
use BusyBird::Version; our $VERSION = $BusyBird::Version::VERSION;
use BusyBird::Main;
use BusyBird::Main::PSGI qw(create_psgi_app);
use Exporter qw(import);

our @EXPORT = our @EXPORT_OK = qw(busybird timeline end);

my $singleton_main;

sub busybird {
    return defined($singleton_main)
        ? $singleton_main : ($singleton_main = BusyBird::Main->new);
}

sub timeline {
    my ($timeline_name) = @_;
    return busybird()->timeline($timeline_name);
}

sub end {
    return create_psgi_app(busybird());
}

1;

__END__

=pod

=head1 NAME

BusyBird - a multi-level Web-based timeline viewer

=head1 SYNOPSIS

In your C<~/.busybird/config.psgi> file...

    use BusyBird;
    
    busybird->set_config(
        time_zone => "+0900",
    );
    
    timeline("twitter_work")->set_config(
        time_zone => "America/Chicago"
    );
    timeline("twitter_private");
    
    end;

=head1 DESCRIPTION

L<BusyBird> is a personal Web-based timeline viewer application.
You can think of it as a Twitter client, but L<BusyBird> is more generic and focused on viewing.

L<BusyBird> accepts data called B<Statuses> from its RESTful Web API.
The received statuses are stored to one or more B<Timelines>.
You can view those statuses in a timeline by a Web browser.

    [ Statuses ]
         |       +----------------+
         |       |    BusyBird    |
        HTTP     |                |
        POST --> | [ Timeline 1 ]----+
                 | [ Timeline 2 ] |  |
                 |       ...      | HTTP
                 +----------------+  |
                                     v
                              [ Web Browser ]
                                     |
                                    YOU

=head2 Features

=over

=item *

L<BusyBird> is extremely B<programmable>.
You are free to customize L<BusyBird> to view any statuses, e.g.,
Twitter tweets, RSS feeds, IRC chat logs, system log files etc.
In fact L<BusyBird> is not much of use without programming.

=item *

L<BusyBird> has well-documented B<Web API>.
You can easily write scripts that GET/POST statuses from/to a L<BusyBird> instance.
Some endpoints support real-time notification via HTTP long-polling.

=item *

L<BusyBird> maintains B<read/unread> states of individual statuses.
You can mark statuses as "read" via Web API.

=item *

L<BusyBird> renders statuses based on their B<< Status Levels >>.
Statuses whose level is below the threshold are dynamically hidden,
so you can focus on more relevant statuses.
Status levels are set by you, not by L<BusyBird>.

=back

=head1 SCREENSHOTS

TBW.

=head1 DOCUMENTATION

=over

=item L<BusyBird::Tutorial>

If you are new to L<BusyBird>, you should read this first.

=item L<BusyBird::WebAPI>

Reference manual of L<BusyBird> Web API.

=item L<BusyBird::Status>

Object structure of L<BusyBird> statuses.

=item L<BusyBird::Config>

How to configure L<BusyBird>.

=item ...and others.

Documentation for various L<BusyBird> modules may be helpful when you customize
your L<BusyBird> instance.

=back

=head1 AS A MODULE

Below is detailed documentation of L<BusyBird> module.
Casual users need not to read it.

As a module, L<BusyBird> maintains a singleton L<BusyBird::Main> object,
and exports some functions to manipulate the singleton.
That way, L<BusyBird> makes it easy for users to write their C<config.psgi> file.

=head1 EXPORTED FUNCTIONS

The following functions are exported by default.

=head2 $main = busybird()

Returns the singleton L<BusyBird::Main> object.

=head2 $timeline = timeline($timeline_name)

Returns the L<BusyBird::Timeline> object named C<$timeline_name> from the singleton.
If there is no such timeline, it automatically creates the timeline.

This is equivalent to C<< busybird()->timeline($timeline_name) >>.

=head2 $psgi_app = end()

Returns a L<PSGI> application object from the singleton L<BusyBird::Main> object.
This is supposed to be called at the end of C<config.psgi> file.

This is equivalent to C<< BusyBird::Main::PSGI::create_psgi_app(busybird()) >>.

=head1 TECHNOLOGIES USED

TBW. License thingy.

=over

=item jQuery

=item Bootstrap

Make sure to mention Glyphicons

=item q.js

=item spin.js

=item ... and a lot of Perl modules

=back

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=head1 LICENSE

Copyright 2013 Toshio Ito.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut
