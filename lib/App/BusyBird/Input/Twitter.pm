package App::BusyBird::Input::Twitter;
use strict;
use warnings;
use App::BusyBird::Util qw(set_param);
use App::BusyBird::Log;
use App::BusyBird::DateTime::Format;
use Time::HiRes qw(sleep);
use JSON;
use Storable qw(dclone);
use Try::Tiny;
use Carp;
use DateTime::TimeZone;

our $VERSION = "0.01";

our $STATUS_TIMEZONE = DateTime::TimeZone->new(name => 'local');
my $DATETIME_FORMATTER = 'App::BusyBird::DateTime::Format';

sub new {
    my ($class, %params) = @_;
    my $self = bless {}, $class;
    $self->set_param(\%params, 'backend', undef, 1);
    $self->set_param(\%params, 'filepath', undef);
    $self->set_param(\%params, 'page_max', 10);
    $self->set_param(\%params, 'page_max_no_since_id', 1);
    $self->set_param(\%params, 'page_next_delay', 0.5);
    $self->{logger} = exists($params{logger}) ? $params{logger} : App::BusyBird::Log->logger;
    $self->{transformer} =
        exists($params{transformer}) ? $params{transformer} : \&transformer_default;
    return $self;
}

sub transformer_default {
    my ($self, $status_arrayref) = @_;
    return [
        map { $self->transform_permalink($_) }
            map { $self->transform_timezone($_) }
                map { $self->transform_status_id($_) }
                    map { $self->transform_search_status($_) } @$status_arrayref ];
}

my %_SEARCH_KEY_MAP = (
    id => 'from_user_id',
    id_str => 'from_user_id_str',
    screen_name => 'from_user',
    profile_image_url => 'profile_image_url',
);

sub transform_search_status {
    my ($self, $status) = @_;
    my $new_status = dclone($status);
    if(exists($status->{created_at})) {
        $new_status->{created_at} = $DATETIME_FORMATTER->format_datetime(
            $DATETIME_FORMATTER->parse_datetime($status->{created_at})
        );
    }
    return $new_status if defined $status->{user};
    $new_status->{user} = {};
    foreach my $new_id (keys %_SEARCH_KEY_MAP) {
        my $orig_id = $_SEARCH_KEY_MAP{$new_id};
        $new_status->{user}{$new_id} = delete $new_status->{$orig_id} if exists $new_status->{$orig_id};
    }
    return $new_status;
}

sub transform_status_id {
    my ($self, $status) = @_;
    my $prefix = $self->{backend}->apiurl;
    $prefix =~ s|/+$||;
    my $new_status = dclone($status);
    foreach my $key (qw(id id_str in_reply_to_status_id in_reply_to_status_id_str)) {
        next if not defined $status->{$key};
        $new_status->{$key} = "$prefix/" . $status->{$key};
        $new_status->{busybird}{original}{$key} = $status->{$key};
    }
    return $new_status;
}

sub transform_permalink {
    my ($self, $status) = @_;
    my $apiurl = $self->{backend}->apiurl;
    my $id;
    {
        no autovivification;
        $id = $status->{busybird}{original}{id}
        || $status->{busybird}{original}{id_str}
            || $status->{id}
                || $status->{id_str};
        return $status if not defined($apiurl);
        return $status if not defined($id);
        return $status if not defined($status->{user}{screen_name});
    }
    $apiurl =~ s|/+$||;
    my $new_status = dclone($status);
    $new_status->{busybird}{status_permalink} = sprintf(
        "%s/%s/status/%s", $apiurl, $status->{user}{screen_name}, $id
    );
    return $new_status;
}

sub transform_timezone {
    my ($self, $status, $timezone) = @_;
    $timezone = $STATUS_TIMEZONE if not defined $timezone;
    my $dt = $DATETIME_FORMATTER->parse_datetime($status->{created_at});
    croak 'Invalid created_at field in a status' if not defined $dt;
    $dt->set_time_zone($timezone);
    my $new_status = dclone($status);
    $new_status->{created_at} = $DATETIME_FORMATTER->format_datetime($dt);
    return $new_status;
}

sub _load_next_since_id_file {
    my ($self) = @_;
    return {} if not defined($self->{filepath});
    open my $file, $self->{filepath} or return undef;
    my $json_text = do { local $/ = undef; <$file> };
    close $file;
    my $since_ids = try {
        decode_json($json_text);
    }catch {
        my $e = shift;
        $self->_log("warn", "failed to decode_json");
        return {};
    };
    $since_ids = {} if not defined $since_ids;
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

sub _normalize_search_result {
    my ($self, $nt_result) = @_;
    if(ref($nt_result) eq 'HASH' && ref($nt_result->{results}) eq 'ARRAY') {
        return $nt_result->{results};
    }else {
        return $nt_result;
    }
}

sub _load_timeline {
    my ($self, $nt_params, $method, @label_params) = @_;
    my %params = defined($nt_params) ? %$nt_params : ();
    if(not defined $method) {
        $method = (caller(1))[3];
        $method =~ s/^.*:://g;
    }
    my $label = "$method," .
        join(",", map { "$_:" . (defined($params{$_}) ? $params{$_} : "") } @label_params);
    my $since_ids = $self->_load_next_since_id_file();
    my $since_id = $since_ids->{$label};
    $params{since_id} = $since_id if !defined($params{since_id}) && defined($since_id);
    my $page_max = defined($params{since_id}) ? $self->{page_max} : $self->{page_max_no_since_id};
    if($method eq 'public_timeline') {
        $page_max = 1;
    }
    my $max_id = undef;
    my @result = ();
    my $load_count = 0;
    my %loaded_ids = ();
    my $next_since_id;
    while($load_count < $page_max) {
        $params{max_id} = $max_id if defined $max_id;
        $self->_log_query($method, \%params);
        my $loaded;
        try {
            $loaded = $self->{backend}->$method({%params});
        }catch {
            my $e = shift;
            $self->_log("error", $e);
        };
        return undef if not defined $loaded;
        $loaded = $self->_normalize_search_result($loaded);
        @$loaded = grep { !$loaded_ids{$_->{id}} } @$loaded;
        last if !@$loaded;
        $loaded_ids{$_->{id}} = 1 foreach @$loaded;
        $max_id = $loaded->[-1]{id};
        $next_since_id = $loaded->[0]{id} if not defined $next_since_id;
        $loaded = $self->{transformer}->($self, $loaded) if defined $self->{transformer};
        if(ref($loaded) ne "ARRAY") {
            croak("transformer must return array-ref");
        }
        push(@result, @$loaded);
        $load_count++;
        sleep($self->{page_next_delay});
    }
    if($load_count == $self->{page_max}) {
        $self->_log("warn", "page has reached the max value of " . $self->{page_max});
    }
    if(defined($next_since_id)) {
        $since_ids->{$label} = $next_since_id;
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
    return $self->_load_timeline($nt_params, undef, qw(q lang locale));
}

1;

=pod

=head1 NAME

App::BusyBird::Input::Twitter - Loader for Twitter API

=head1 VERSION

Version 0.01


=head1 SYNOPSIS

    use App::BusyBird::Input::Twitter;
    use Net::Twitter;
    
    my $input = App::BusyBird::Input::Twitter->new(
        backend => Net::Twitter->new(
            traits => [qw(OAuth API::REST API::Search)],
            consumer_key => "YOUR_CONSUMER_KEY_HERE",
            consumer_secret => "YOUR_CONSUMER_SECRET_HERE",
            access_token => "YOUR_ACCESS_TOKEN_HERE",
            access_token_secret => "YOUR_ACCESS_TOKEN_SECRET_HERE",
            ssl => 1,
    
            #### If you access to somewhere other than twitter.com,
            #### set the apiurl option
            ## apiurl => "http://example.com/api/",
        ),
        filepath => 'next_since_ids.json'
    );
    
    ## First call to home_timeline
    my $arrayref_of_statuses = $input->home_timeline();
    
    ## The latest loaded status ID is saved to next_since_ids.json
    
    ## Subsequent calls to home_timeline automatically load
    ## all statuses that have not been loaded yet.
    $arrayref_of_statuses = $input->home_timeline();
    
    
    ## You can load other timelines as well.
    $arrayref_of_statuses = $input->user_timeline({screen_name => 'hoge'});


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
The file will be read to set C<since_id> param for the next request,
so that it can always load all the unread statuses.


=item *

Convert status IDs to include the source of the statuses.
This prevents ID conflict between statuses from different sources.


=item *

Add BusyBird-specific fields to the statuses.


=item *

Normalize status objects from Search API.

It might be unnecesary in Twitter API v1.1, other Twitter API
implementations like identi.ca might need it.


=item *

It catches Net::Twitter's exception internally.
If an exception is thrown, it is logged and C<undef> is returned.


=back


=head1 CLASS METHODS

=head2 $input = App::BusyBird::Input::Twitter->new(%options);

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

Logger object. By default L<App::BusyBird::Log> object is used.

Setting it to C<undef> suppresses logging.

=item transformer (optional)

A subroutine reference that transforms the result from Net::Twitter methods.

The transformer takes two arguments.
The first is the L<App::BusyBird::Input::Twitter> object.
The second is the array-ref of status objects obtained by Net::Twitter methods (C<home_timeline>, C<user_timeline> etc.).

The output from the transformer is an array-ref of the transformed result.

By default, C<transformer> is C<transformer_default> function in this module.

Setting C<transformer> to C<undef> suppresses any transformation.

=back

=head1 OBJECT METHODS

=head2 $status_arrayref = $input->home_timeline($options_hashref)

=head2 $status_arrayref = $input->user_timeline($options_hashref)

=head2 $status_arrayref = $input->list_statuses($options_hashref)

=head2 $status_arrayref = $input->public_statuses($options_hashref)

=head2 $status_arrayref = $input->search($options_hashref)

Wrapper methods for corresponding L<Net::Twitter> methods. See L<Net::Twitter> for specification of C<$options_hashref>.

If C<since_id> is given by C<$options_hashref> or it is loaded from the file specified by C<filepath> option,
these wrapper methods repeatedly call L<Net::Twitter>'s corresponding methods to load a complete timeline newer than C<since_id>.
If C<filepath> option is enabled, the latest ID of the loaded status is saved to the file.

The max number of calling the backend L<Net::Twitter> methods is limited to C<page_max> option
if C<since_id> is specified or loaded from the file. The max number is limited to C<page_max_no_since_id> option
if C<since_id> is not specified.

If the operation succeeds, the return value of these methods is an array-ref of status objects transformed by C<transformer> option.
If the backend L<Net::Twitter> methods throw an exception due to network failure or something,
the exception is catched and C<undef> is returned.


=head2 $transformed_status_arrayref = $input->transformer_default($status_arrayref)

Default C<transformer> of results from L<Net::Twitter>.
In fact this is just applying the following C<transform_*> methods to every status.


=head2 $normal_status = $input->transform_search_status($search_status)

Transforms a status object returned by Twitter's Search API v1.0 into something more like a normal status object.

This method does not modify the input C<$search_status>. The transformation is done to its clone.


=head2 $transformed_status = $input->transform_status_id($status)

Transforms a status's ID fields so that they include API URL of the source.
This transformation is recommended when you load statuses from multiple sources, e.g. twitter.com and identi.ca.

This method does not modify the input C<$status>. The transformation is done to its clone.

The original IDs are saved under C<< $transformed_status->{busybird}{original} >>


=head2 $transformed_status = $input->transform_timezone($status, [$timezone_string])

Transforms the timezone of a status's C<created_at> field to the specified C<$timezone_string>.
If C<$timezone_string> is omitted, C<$App::BusyBird::Input::Twitter::STATUS_TIMEZONE>
(a C<DateTime::TimeZone> object) is used, which represents the local timezone by default.


C<$timezone_string> must be a string that L<DateTime::TimeZone> module can understand.

This method does not modify the input C<$status>. The transformation is done to its clone.

=head2 $transformed_status = $input->transform_permalink($status)

Adds a permalink field to the transformed status.

The permalink is stored in C<< $transformed_status->{busybird}{status_permalink}. >>

This method does not modify the input C<$status>. The transformation is done to its clone.


=head1 AUTHOR

Toshio Ito

=cut
