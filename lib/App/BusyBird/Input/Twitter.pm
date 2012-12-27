package App::BusyBird::Input::Twitter;

use strict;
use warnings;
use App::BusyBird::Util qw(set_param);
use App::BusyBird::Log;
use Time::HiRes qw(sleep);
use JSON;
use Try::Tiny;
use Carp;

sub new {
    my ($class, %params) = @_;
    my $self = bless {}, $class;
    $self->set_param(\%params, 'backend', undef, 1);
    $self->set_param(\%params, 'filepath', undef);
    $self->set_param(\%params, 'page_max', 10);
    $self->set_param(\%params, 'page_max_no_since_id', 1);
    $self->set_param(\%params, 'page_next_delay', 0.5);
    $self->{logger} = exists($params{logger}) ? $params{logger} : App::BusyBird::Log->logger;
    return $self;
}

sub _load_next_since_id_file {
    my ($self) = @_;
    return undef if not defined($self->{filepath});
    open my $file, $self->{filepath} or return undef;
    my $json_text = do { local $/ = undef; <$file> };
    close $file;
    my $since_ids = try {
        decode_json($json_text);
    };
    return $since_ids;
}

sub _log {
    my ($self, $level, $msg) = @_;
    $self->{logger}->log($level, $msg) if defined $self->{logger};
}

sub _save_next_since_id_file {
    my ($self, $since_ids) = @_;
    return if not defined($self->{filepath});
    open my $file, ">", $self->{filepath} or die "Cannot open $self->{filepath} for write: $!";
    try {
        print $file encode_json($since_ids);
    }catch {
        my $e = shift;
        $self->_log("error", $e);
    };
    close $file;
}

sub _log_query {
    my ($self, $method, $params) = @_;
    $self->_log("info", sprintf(
        "%s: method: %s, args: %s", __PACKAGE__, $method,
        join(", ", map {"$_: " . (defined($params->{$_}) ? $params->{$_} : "[undef]")} keys %$params)
    ));
}

sub _load_timeline {
    my ($self, $nt_params, $method, @label_params) = @_;
    $nt_params ||= {};
    if(not defined $method) {
        $method = (caller(1))[3];
        $method =~ s/^.*:://g;
    }
    my $label = "$method," .
        join(",", map { "$_:" . (defined($nt_params->{$_}) ? $nt_params->{$_} : "") } @label_params);
    my $since_ids = $self->_load_next_since_id_file();
    my $since_id = $since_ids->{$label};
    $nt_params->{since_id} = $since_id if !defined($nt_params->{since_id}) && defined($since_id);
    my $page_max = defined($nt_params->{since_id}) ? $self->{page_max} : $self->{page_max_no_since_id};
    my $max_id = undef;
    my @result = ();
    my $load_count = 0;
    my %loaded_ids = ();
    while($load_count < $page_max) {
        $nt_params->{max_id} = $max_id if defined $max_id;
        $self->_log_query($method, $nt_params);
        my $loaded;
        try {
            $loaded = $self->{backend}->$method($nt_params);
        }catch {
            my $e = shift;
            $self->_log("error", $e);
        };
        last if not defined $loaded;
        @$loaded = grep { !$loaded_ids{$_->{id}} } @$loaded;
        last if !@$loaded;
        push(@result, @$loaded);
        $loaded_ids{$_->{id}} = 1 foreach @$loaded;
        $max_id = $loaded->[-1]{id};
        $load_count++;
        sleep($self->{page_next_delay});
    }
    if($load_count == $self->{page_max}) {
        $self->_log("warn", "page has reached the max value of " . $self->{page_max});
    }
    if(@result) {
        $since_ids->{$label} = $result[0]->{id};
        $self->_save_next_since_id_file($since_ids);
    }
    return \@result;
}

sub user_timeline {
    my ($self, $nt_params) = @_;
    return $self->_load_timeline($nt_params, undef, qw(user_id screen_name));
}

sub public_timeline {
    my ($self, $nt_params) = @_;
    return $self->_load_timeline($nt_params);
}

sub home_timeline {
    my ($self, $nt_params) = @_;
    return $self->_load_timeline($nt_params);
}

sub list_statuses {
    my ($self, $nt_params) = @_;
    return $self->_load_timeline($nt_params, undef, qw(user list_id));
}

sub search {
    my ($self, $nt_params) = @_;
    return $self->_load_time($nt_params, undef, qw(q lang locale));
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

=item filepath (optional)

File path for saving and loading the next since_id.
If this option is not specified, no file will be created or loaded.

=item page_max (optional)

Maximum number of pages this module tries to load when since_id is given.

=item page_max_no_since_id (optional)

Maximum number of pages this module tries to load when no since_id is given.

=item page_next_delay (optional)

Delay in seconds before loading the next page.

=item logger (optional)

Logger object. By default App::BusBird::Log object is used.

Setting it to C<undef> suppresses logging.

=back



=cut
