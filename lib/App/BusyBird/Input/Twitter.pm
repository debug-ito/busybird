package App::BusyBird::Input::Twitter;

use strict;
use warnings;
use App::BusyBird::Util qw(setParam);
use App::BusyBird::Log qw(bblog);
use Time::HiRes qw(sleep);

sub new {
    my ($class, %params) = @_;
    my $self = bless {}, $class;
    $self->setParam(\%params, 'backend', undef, 1);
    $self->setParam(\%params, 'path_base', undef);
    $self->setParam(\%params, 'page_max', 10);
    $self->setParam(\%params, 'page_max_no_since_id', 1);
    $self->setParam(\%params, 'page_next_delay', 0.5);
    return $self;
}

sub _loadTimeFile {
    my ($self, $label) = @_;
    return undef if not defined($self->{path_base});
    my $filename = $self->{path_base} . $label;
    open my $file, $filename or return undef;
    my $since_id = <$file>;
    close $file;
    $since_id =~ s/\s+$//;
    return $since_id;
}

sub _saveTimeFile {
    my ($self, $label, $since_id) = @_;
    return if not defined($self->{path_base});
    my $filename = $self->{path_base} . $label;
    open my $file, ">", $filename or die "Cannot open $filename for write: $!";
    print $file "$since_id\n";
    close $file;
}

sub _logQuery {
    my ($self, $method, $params) = @_;
    bblog("info", sprintf(
        "%s: method: %s, args: %s", __PACKAGE__, $method,
        join(", ", map {"$_: " . (defined($params->{$_}) ? $params->{$_} : "[undef]")} keys %$params)
    ));
}

sub user_timeline {
    my ($self, $label, $nt_params) = @_;
    $label ||= "";
    my $since_id = $self->_loadTimeFile($label);
    $nt_params->{since_id} = $since_id if !defined($nt_params->{since_id}) && defined($since_id);
    my $page_max = defined($nt_params->{since_id}) ? $self->{page_max} : $self->{page_max_no_since_id};
    my $max_id = undef;
    my @result = ();
    my $load_count = 0;
    my %loaded_ids = ();
    while($load_count < $page_max) {
        $nt_params->{max_id} = $max_id if defined $max_id;
        my $loaded = $self->{backend}->user_timeline($nt_params);
        $self->_logQuery("user_timeline", $nt_params);
        @$loaded = grep { !$loaded_ids{$_->{id}} } @$loaded;
        last if !@$loaded;
        push(@result, @$loaded);
        $loaded_ids{$_->{id}} = 1 foreach @$loaded;
        $max_id = $loaded->[-1]{id};
        $load_count++;
        sleep($self->{page_next_delay});
    }
    if($load_count == $self->{page_max}) {
        bblog("warn", "page has reached the max value of " . $self->{page_max});
    }
    if(@result) {
        $self->_saveTimeFile($label, $result[0]->{id});
    }
    return \@result;
}

1;

=pod

=head1 NAME

App::BusyBird::Input::Twitter - Loader for Twitter API


=head1 DESCRIPTION

This module is a wrapper for L<Net::Twitter> to make it easy
to load a timeline for L<App::BusyBird>.

=head1 FEATURES

=over

=item *

It repeats requests to load a timeline that expands over multiple pages.
C<max_id> param for the requests are adjusted automatically.

=item *

Optionally it saves the latest status ID to a file.
The file will be read to set C<since_id> param for the next request.

=item *

Convert status IDs to include the source of the statuses.
This prevents ID conflict between statuses from different sources.

=item *

Add BusyBidrd-specific fields to the statuses.


=item *

Normalize status objects for Search API.
It might be unnecesary in Twitter API v1.1, but what about other Twitter API
implementation like identi.ca?

Also, Net::Twitter has its own plan for supporting API v1.1.
See also L<https://twitter.com/semifor/status/273442692371992578>

=back


=head1 CLASS METHODS

=head2 $bbtw = App::BusyBird::Input::Twitter->new(%options);

Creates the object with the following C<%options>.

=over

=item backend (mandatory)

Backend L<Net::Twitter> object.

=item path_base (optional)

File path base for saving next since_id.
If this option is not specified, no file will be created.

=item page_max (optional)

Maximum number of pages this module tries to load when since_id is given.

=item page_max_no_since_id (optional)

Maximum number of pages this module tries to load when no since_id is given.

=item page_next_delay (optional)

Delay in seconds before loading the next page.

=back



=cut
