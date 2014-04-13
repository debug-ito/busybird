package BusyBird::Main::PSGI::View;
use strict;
use warnings;
use BusyBird::Util qw(set_param split_with_entities);
use Carp;
use Try::Tiny;
use Scalar::Util qw(weaken);
use JSON qw(to_json);
use Text::Xslate qw(html_builder html_escape);
use File::Spec;
use Encode ();
use JavaScript::Value::Escape ();
use DateTime::TimeZone;
use BusyBird::DateTime::Format;
use Cache::Memory::Simple;
use Plack::Util ();
use Tie::IxHash;
use BusyBird::Version;
our $VERSION = $BusyBird::Version::VERSION;

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        main_obj => undef,
        renderer => undef,
    }, $class;
    $self->set_param(\%args, "main_obj", undef, 1);
    my $sharedir = $self->{main_obj}->get_config('sharedir_path');
    $sharedir =~ s{/+$}{};
    $self->{renderer} = Text::Xslate->new(
        path => [ File::Spec->catdir($sharedir, 'www', 'templates') ],
        cache_dir => File::Spec->tmpdir,
        syntax => 'TTerse',
        function => $self->template_functions(),
        ## warn_handler => sub { ... },
    );
    return $self;
}

sub response_notfound {
    my ($self, $message) = @_;
    $message ||= 'Not Found';
    return ['404',
            ['Content-Type' => 'text/plain',
             'Content-Length' => length($message)],
            [$message]];
}

sub response_error_html {
    my ($self, $http_code, $message) = @_;
    return $self->_response_template(
        template => 'error.tt', args => {error => $message},
        code => $http_code
    );
}


sub response_json {
    my ($self, $res_code, $response_object) = @_;
    my $message = try {
        die "response must not be undef" if not defined $response_object;
        if($res_code eq '200' && ref($response_object) eq "HASH" && !exists($response_object->{error})) {
            $response_object->{error} = undef;
        }
        to_json($response_object, {ascii => 1})
    }catch {
        undef
    };
    if(defined($message)) {
        return [
            $res_code, ['Content-Type' => 'application/json; charset=utf-8'],
            [$message]
        ];
    }else {
        return $self->response_json(500, {error => "error while encoding to JSON."});
    }
}

sub _response_template {
    my ($self, %args) = @_;
    my $template_name = delete $args{template};
    croak 'template parameter is mandatory' if not defined $template_name;
    my $args = delete $args{args};
    my $code = delete $args{code} || 200;
    my $headers = delete $args{headers} || [];
    if(!Plack::Util::header_exists($headers, 'Content-Type')) {
        push(@$headers, 'Content-Type', 'text/html; charset=utf8');
    }
    my $ret = Encode::encode('utf8', $self->{renderer}->render($template_name, $args));
    return [$code, $headers, [$ret]];
}


my $REGEXP_URL_CHAR = qr{[A-Za-z0-9~\/._!\?\&=\-%#\+:\;,\@\']};
my $REGEXP_HTTP_URL = qr{https?:\/\/$REGEXP_URL_CHAR+};
my $REGEXP_ABSOLUTE_PATH = qr{/$REGEXP_URL_CHAR*};
my %URL_ATTRIBUTES = map { $_ => 1 } qw(src href);

sub _is_valid_link_url {
    my ($url) = @_;
    $url = "" if not defined $url;
    return ($url =~ /^(?:$REGEXP_HTTP_URL|$REGEXP_ABSOLUTE_PATH)$/);
}

sub _html_attributes_string {
    my ($mandatory_attrs_ref, @attr) = @_;
    for(my $i = 0 ; $i < $#attr ; $i += 2) {
        $attr[$i] = lc($attr[$i]);
    }
    tie(my %attr, 'Tie::IxHash', @attr);
    foreach my $attr_key (@$mandatory_attrs_ref) {
        croak "$attr_key attribute is mandatory" if not defined $attr{$attr_key};
    }
    my @attr_strings = ();
    foreach my $attr_key (keys %attr) {
        my $attr_value = $attr{$attr_key};
        my $value_str;
        if($URL_ATTRIBUTES{$attr_key}) {
            croak "$attr_key attribute is invalid as a URL" if not _is_valid_link_url($attr_value);
            $value_str = $attr_value;
        }else {
            $value_str = html_escape($attr_value);
        }
        push(@attr_strings, html_escape($attr_key) . qq{="$value_str"});
    }
    return join(" ", @attr_strings);
}

sub _html_link {
    my ($text, @attr) = @_;
    $text = "" if not defined $text;
    my $escaped_text = html_escape($text);
    return try {
        my $attr_str = _html_attributes_string(['href'], @attr);
        return qq{<a $attr_str>$escaped_text</a>};
    }catch {
        return $escaped_text;
    };
}

sub template_functions {
    return {
        js => \&JavaScript::Value::Escape::js,
        link => html_builder(\&_html_link),
        image => html_builder {
            my (@attr) = @_;
            return try {
                my $attr_str = _html_attributes_string(['src'], @attr);
                return qq{<img $attr_str />}
            }catch {
                return "";
            };
        },
        bb_level => sub {
            my $level = shift;
            $level = 0 if not defined $level;
            return $level;
        },
    };
}

sub template_functions_for_timeline {
    my ($self, $timeline_name) = @_;
    weaken $self;  ## in case the functions are kept by $self
    return {
        bb_timestamp => sub {
            my ($timestamp_string) = @_;
            return "" if !$timestamp_string;
            my $timezone = $self->_get_timezone($self->{main_obj}->get_timeline_config($timeline_name, "time_zone"));
            my $dt = BusyBird::DateTime::Format->parse_datetime($timestamp_string);
            return "" if !defined($dt);
            $dt->set_time_zone($timezone);
            $dt->set_locale($self->{main_obj}->get_timeline_config($timeline_name, "time_locale"));
            return $dt->strftime($self->{main_obj}->get_timeline_config($timeline_name, "time_format"));
        },
        bb_status_permalink => sub {
            my ($status) = @_;
            my $builder = $self->{main_obj}->get_timeline_config($timeline_name, "status_permalink_builder");
            my $url = $builder->($status);
            return (_is_valid_link_url($url) ? $url : "");
        },
        bb_text => html_builder {
            my $status = shift;
            return "" if not defined $status->{text};
            my $segments_ref = split_with_entities($status->{text}, $status->{entities});
            my $result_text = "";
            foreach my $segment (@$segments_ref) {
                $result_text .= try {
                    die "no entity" if not defined $segment->{entity};
                    my $url_builder = $self->{main_obj}->get_timeline_config($timeline_name, "$segment->{type}_entity_url_builder");
                    my $text_builder = $self->{main_obj}->get_timeline_config($timeline_name, "$segment->{type}_entity_text_builder");
                    die "no builder" if !defined($url_builder) || !defined($text_builder);
                    my $url_str = $url_builder->($segment->{text}, $segment->{entity}, $status);
                    die "invalid URL" if !_is_valid_link_url($url_str);
                    my $text_str = $text_builder->($segment->{text}, $segment->{entity}, $status);
                    $text_str = "" if not defined $text_str;
                    $text_str = html_escape($text_str);
                    return qq{<a href="$url_str">$text_str</a>};
                }catch {
                    return _escape_and_linkify($segment->{text});
                };
            }
            return $result_text;
        }
    };
}

{
    my $timezone_cache = Cache::Memory::Simple->new();
    my $CACHE_EXPIRATION_TIME = 3600 * 24;
    my $CACHE_SIZE_LIMIT = 100;
    sub _get_timezone {
        my ($self, $timezone_string) = @_;
        if($timezone_cache->count > $CACHE_SIZE_LIMIT) {
            $timezone_cache->purge();
            if($timezone_cache->count > $CACHE_SIZE_LIMIT) {
                $timezone_cache->delete_all();
            }
        }
        return $timezone_cache->get_or_set($timezone_string, sub {
            return DateTime::TimeZone->new(name => $timezone_string),
        }, $CACHE_EXPIRATION_TIME);
    }
}

sub _escape_and_linkify {
    my ($text) = @_;
    my $result_text = "";
    my $remaining_index = 0;
    while($text =~ m/\G(.*?)($REGEXP_HTTP_URL)/sg) {
        my ($other_text, $url) = ($1, $2);
        $result_text .= html_escape($other_text);
        $result_text .= _html_link($url, href => $url);
        $remaining_index = pos($text);
    }
    $result_text .= html_escape(substr($text, $remaining_index));
    return $result_text;
}

sub _format_status_html_destructive {
    my ($self, $status, $timeline_name) = @_;
    $timeline_name = "" if not defined $timeline_name;
    if(defined($status->{retweeted_status}) && ref($status->{retweeted_status}) eq "HASH") {
        my $retweet = $status->{retweeted_status};
        $status->{busybird}{retweeted_by_user} = $status->{user};
        foreach my $key (qw(text created_at user entities)) {
            $status->{$key} = $retweet->{$key};
        }
    }
    return $self->{renderer}->render(
        "status.tt",
        {s => $status, %{$self->template_functions_for_timeline($timeline_name)}}
    );
}

my %RESPONSE_FORMATTER_FOR_TL_GET_STATUSES = (
    html => sub {
        my ($self, $timeline_name, $code, $response_object) = @_;
        if($code == 200) {
            my $result = "";
            foreach my $status (@{$response_object->{statuses}}) {
                $result .= $self->_format_status_html_destructive($status, $timeline_name);
            }
            $result = Encode::encode('utf8', $result);
            return [200, ['Content-Type', 'text/html; charset=utf8'], [$result]];
        }else {
            return $self->response_error_html($code, $response_object->{error});
        }
    },
    json => sub {
        my ($self, $timeline_name, $code, $response_object) = @_;
        return $self->response_json($code, $response_object);
    },
);

sub response_statuses {
    my ($self, %args) = @_;
    if(!defined($args{statuses}) && !defined($args{error})) {
        croak "stautses or error parameter is mandatory";
    }
    foreach my $param_key (qw(http_code format)) {
        croak "$param_key parameter is mandatory" if not defined($args{$param_key});
    }
    my $formatter = $RESPONSE_FORMATTER_FOR_TL_GET_STATUSES{lc($args{format})};
    if(!defined($formatter)) {
        $formatter = $RESPONSE_FORMATTER_FOR_TL_GET_STATUSES{html};
        delete $args{statuses};
        $args{error} = "Unknown format: $args{format}";
        $args{http_code} = 400;
    }
    return $formatter->($self, $args{timeline_name}, $args{http_code},
                        defined($args{error}) ? {error => $args{error}}
                                              : {error => undef, statuses => $args{statuses}});
}

sub response_timeline {
    my ($self, $timeline_name, $script_name) = @_;
    my $timeline = $self->{main_obj}->get_timeline($timeline_name);
    return $self->response_notfound("Cannot find $timeline_name") if not defined($timeline);
    
    return $self->_response_template(
        template => "timeline.tt",
        args => {
            timeline_name => $timeline_name,
            script_name => $script_name,
            post_button_url => $self->{main_obj}->get_timeline_config($timeline_name, "post_button_url")
        }
    );
}

sub response_timeline_list {
    my ($self, %args) = @_;
    foreach my $key (qw(script_name timeline_unacked_counts total_page_num cur_page)) {
        croak "$key parameter is mandatory" if not defined $args{$key};
    }
    croak "timeline_unacked_counts must be an array-ref" if ref($args{timeline_unacked_counts}) ne "ARRAY";
    
    my %input_args = (last_page => $args{total_page_num} - 1);
    foreach my $input_key (qw(script_name cur_page)) {
        $input_args{$input_key} = $args{$input_key};
    }
    
    $input_args{timeline_unacked_counts_json} = [map {
        +{name => $_->{name}, counts_json => to_json($_->{counts})}
    } @{$args{timeline_unacked_counts}}];
    
    my $pager_entry_max = $self->{main_obj}->get_config('timeline_list_pager_entry_max');
    my $left_margin = int($pager_entry_max / 2);
    my $right_margin = $pager_entry_max - $left_margin;
    $input_args{page_list} =
          $args{total_page_num} <= $pager_entry_max ? [0 .. ($args{total_page_num} - 1)]
        : $args{cur_page} <= $left_margin           ? [0 .. ($pager_entry_max - 1)]
        : $args{cur_page} >= ($args{total_page_num} - $right_margin)
                                                    ? [($args{total_page_num} - $pager_entry_max) .. ($args{total_page_num} - 1)]
                                                    : [($args{cur_page} - $left_margin) .. ($args{cur_page} + $right_margin - 1)];
    return $self->_response_template(
        template => "timeline_list.tt",
        args => \%input_args,
    );
}

1;

__END__

=pod

=head1 NAME

BusyBird::Main::PSGI::View - view renderer for BusyBird::Main

=head1 DESCRIPTION

This is a view renderer object for L<BusyBird::Main>.

End-users should not use this module directly.
Specification in this document may be changed in the future.


=head1 CLASS METHODS

=head2 $view = BusyBird::Main::PSGI::View->new(%args)

The constructor.

Fields in C<%args> are:

=over

=item C<main_obj> => L<BusyBird::Main> OBJECT (mandatory)

=back

=head1 OBJECT METHODS

=head2 $psgi_response = $view->response_notfound([$message])

Returns a simple "404 Not Found" page.

C<$message> is the message body, which is optional.

Return value C<$psgi_response> is a L<PSGI> response object.

=head2 $psgi_response = $view->response_error_html($http_code, $message)

Returns an HTTP error response in HTML.

C<$http_code> is HTTP response code, which should be 4** or 5**.
C<$message> is a human-readable error message.

Return value C<$psgi_response> is a L<PSGI> response object.


=head2 $psgi_response = $view->response_json($http_code, $response_object)

Returns a response object whose content is a JSON-fomatted object.

C<$http_code> is the HTTP response code such as "200", "404" and "500".
C<$response_object> is a reference to an object.

Return value C<$psgi_response> is a L<PSGI> response object.
Its content is C<$response_object> formatted in JSON.

C<$response_object> must be encodable by L<JSON>.
Otherwise, it returns a L<PSGI> response with HTTP code of 500 (Internal Server Error).

If C<$http_code> is 200, C<$response_object> is a hash-ref and C<< $response_object->{error} >> does not exist,
C<< $response_object->{error} >> is automatically set to C<undef>, indicating the response is successful.

=head2 $psgi_response = $view->response_statuses(%args)

Returns a L<PSGI> response object for given status objects.

Fields in C<%args> are:

=over

=item C<statuses> => ARRAYREF_OF_STATUSES (semi-optional)

Array-ref of statuses to be rendered.
You must set either C<statuses> field or C<error> field.
If not, it croaks.

=item C<error> => STR (semi-optional)

Error string to be rendered.
This field must be set when you don't have statuses due to some error.

=item C<http_code> => INT (mandatory)

HTTP response code.

=item C<format> => STR (mandatory)

A string specifying rendering format.
Possible formats are: C<"html">, C<"json">.
If unknown format is given, it returns "400 Bad Request" error response.

=item C<timeline_name> => STR (optional)

A string of timeline name for the statuses.

=back

=head2 $psgi_response = $view->response_timeline($timeline_name, $script_name)

Returns a L<PSGI> response object of the top view for a timeline.

C<$timeline_name> is a string of timeline name to be rendered.
If the timeline does not exist in C<$view>'s L<BusyBird::Main> object, it returns "404 Not Found" response.

C<$script_name> is the base path for internal hyperlinks.
It should be C<SCRIPT_NAME> of the C<PSGI> environment.

=head2 $psgi_response = $view->response_timeline_list(%args)

Returns a L<PSGI> response object of the view of timeline list.

Fields in C<%args> are:

=over

=item C<script_name> => STR (mandatory)

The base path for internal hyperlinks known as C<SCRIPT_NAME>.

=item C<timeline_unacked_counts> => ARRAYREF (mandatory)

The data structure keeping the initial unacked counts for timelines.
Its structure is like

    [
      {name => "first timeline name", counts => {total => 0}},
      {name => "second timeline name", counts => {
          total => 10,
          0 => 5,
          1 => 3
          2 => 2
      }}
    ]


=item C<total_page_num> => INT (mandatory)

Total number of pages for listing all timelines.

=item C<cur_page> => INT (mandatory)

The current page number of the timeline list. The page number starts with 0.

=back



=head2 $functions = $view->template_functions()

Returns a hash-ref of subroutine references for template rendering.
They are supposed to be called from L<Text::Xslate> templates.

C<$functions> contain the following keys. All of their values are subroutine references.

=over

=item C<js> => CODEREF($text)

Escapes JavaScript value.

=item C<link> => CODEREF($text, %attr)

Linkifies C<$text> with C<< <a> >> tag with C<%attr> attributes. C<$text> will be HTML-escaped.
If C<< $attr{href} >> does not look like a valid link URL, it returns the escaped C<$text> only.

=item C<image> => CODEREF(%attr)

Returns C<< <img> >> tag with C<%attr> attributes.
If C<< $attr{src} >> does not look like a valid image URL, it returns an empty string.

=item C<bb_level> => CODEREF($level)

Formats status level. C<$level> may be C<undef>, in which case the level is assumed to be 0.


=back

=head2 $functions = $view->template_functions_for_timeline($timeline_name)

Returns a hash-ref of subroutine references for template rendering.
They are supposed to be called from L<Text::Xslate> templates.

C<$timeline_name> is the name of a timeline. C<$functions> is the set of functions that are dependent on the timeline's configuration.

C<$functions> contain the following keys. All of their values are subroutine references.

=over

=item C<bb_timestamp> => CODEREF($timestamp_str)

Returns a timestamp string formatted with the timeline's configuration.
C<$timestamp_str> is the timestamp in status objects such as C<< $status->{created_at} >>.

=item C<bb_status_permalink> => CODEREF($status)

Returns the permalink URL for the status.

=item C<bb_text> => CODEREF($status)

Returns the HTML text for the status.

=back

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut
