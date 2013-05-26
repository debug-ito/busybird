package BusyBird::Main::PSGI::View;
use strict;
use warnings;
use BusyBird::Util qw(set_param);
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
        function => $self->_template_functions(),
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


my $REGEXP_HTTP_URL = qr{https?:\/\/[A-Za-z0-9~\/._!\?\&=\-%#\+:\;,\@\']+};

sub _html_link {
    my ($text, %attr) = @_;
    $text = "" if not defined $text;
    return try {
        die "no attr" if not $attr{href};
        die "invalid url" if $attr{href} !~ $REGEXP_HTTP_URL;
        my $href_attr = qq{href="$attr{href}"};
        my $attrs = join(" ", $href_attr,
                         map { html_escape($_) . q{="} . html_escape($attr{$_})  . q{"} } keys %attr);
        return qq{<a $attrs>}. html_escape($text) . qq{</a>}
    }catch {
        return html_escape($text);
    };
}

sub _template_functions {
    my ($self) = @_;
    weaken $self;
    return {
        js => \&JavaScript::Value::Escape::js,
        format_timestamp => sub {
            my ($timestamp_string, $timeline_name) = @_;
            return "" if !$timestamp_string;
            my $timezone = $self->_get_timezone($self->{main_obj}->get_timeline_config($timeline_name, "time_zone"));
            my $dt = BusyBird::DateTime::Format->parse_datetime($timestamp_string);
            return "" if !defined($dt);
            $dt->set_time_zone($timezone);
            $dt->set_locale($self->{main_obj}->get_timeline_config($timeline_name, "time_locale"));
            return $dt->strftime($self->{main_obj}->get_timeline_config($timeline_name, "time_format"));
        },
        link => html_builder(\&_html_link),
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
        ## $result_text .= qq{<a href="$url">} . html_escape($url) . qq{</a>};
        $result_text .= _html_link($url, href => $url);
        $remaining_index = pos($text);
    }
    $result_text .= html_escape(substr($text, $remaining_index));
    return $result_text;
}

sub _format_status_html_destructive {
    my ($self, $status, $timeline_name) = @_;
    if(!defined($status->{busybird}{level})) {
        $status->{busybird}{level} = 0;
    }
    if(defined($status->{text})) {
        $status->{text} = Text::Xslate::mark_raw(_escape_and_linkify($status->{text}));
    }
    $timeline_name = "" if not defined $timeline_name;
    return $self->{renderer}->render("status.tt", {s => $status, timeline => $timeline_name});
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
            return $self->_response_template(
                template => 'error.tt', args => {error => $response_object->{error}},
                code => $code
            );
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

Returns a "404 Not Found" page.

C<$message> is the message body, which is optional.

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

C<$timeline_name> is the name of a timeline. C<$functions> is the set of functions that are dependent of the timeline's configuration.

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
