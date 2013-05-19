package BusyBird::Main::PSGI;
use strict;
use warnings;
use BusyBird::Util qw(set_param);
use Router::Simple;
use Plack::Request;
use Plack::Builder ();
use Plack::App::File;
use Plack::Util ();
use Try::Tiny;
use JSON qw(decode_json encode_json to_json);
use Scalar::Util qw(looks_like_number weaken);
use Carp;
use Text::Xslate qw(html_builder);
use File::Spec;
use Encode ();
use JavaScript::Value::Escape ();
use DateTime::TimeZone;
use BusyBird::DateTime::Format;
use Cache::Memory::Simple;

sub create_psgi_app {
    my ($class, $main_obj) = @_;
    my $self = $class->_new(main_obj => $main_obj);
    return $self->_to_app;
}

sub _new {
    my ($class, %params) = @_;
    my $self = bless {
        router => Router::Simple->new,
        renderer => undef
    }, $class;
    $self->set_param(\%params, "main_obj", undef, 1);
    $self->{renderer} = Text::Xslate->new(
        path => [ File::Spec->catdir($self->_sharedir, 'www', 'templates') ],
        cache_dir => File::Spec->tmpdir,
        syntax => 'TTerse',
        function => $self->_template_functions(),
        ## warn_handler => sub { ... },
    );
    $self->_build_routes();
    return $self;
}

sub _sharedir {
    my ($self) = @_;
    my $path = $self->{main_obj}->get_config('sharedir_path');
    $path =~ s{/+$}{};
    return $path;
}

sub _template_functions {
    my ($self) = @_;
    weaken $self;
    return {
        js => \&JavaScript::Value::Escape::js,
        format_timestamp => sub {
            my ($timestamp_string) = @_;
            return "" if !$timestamp_string;
            my $timezone = $self->_get_timezone($self->{main_obj}->get_config("time_zone"));
            my $dt = BusyBird::DateTime::Format->parse_datetime($timestamp_string);
            return "" if !defined($dt);
            $dt->set_time_zone($timezone);
            $dt->set_locale($ENV{LC_TIME}) if $ENV{LC_TIME};
            return $dt->strftime($self->{main_obj}->get_config("time_format"));
        },
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

sub _to_app {
    my $self = shift;
    return Plack::Builder::builder {
        Plack::Builder::enable 'ContentLength';
        Plack::Builder::mount '/static' => Plack::App::File->new(
            root => File::Spec->catdir($self->_sharedir, 'www', 'static')
        )->to_app;
        Plack::Builder::mount '/' => $self->_my_app;
    };
}

sub _my_app {
    my ($self) = @_;
    return sub {
        my ($env) = @_;
        if(my $dest = $self->{router}->match($env)) {
            my $req = Plack::Request->new($env);
            my $code = $dest->{code};
            my $method = $dest->{method};
            return defined($code) ? $code->($self, $req, $dest) : $self->$method($req, $dest);
        }else {
            return _notfound_response();
        }
    };
}

sub _build_routes {
    my ($self) = @_;
    my $tl_mapper = $self->{router}->submapper(
        '/timelines/{timeline}', {}
    );
    $tl_mapper->connect('/statuses.{format}',
                        {method => '_handle_tl_get_statuses'}, {method => 'GET'});
    $tl_mapper->connect('/statuses.json',
                        {method => '_handle_tl_post_statuses'}, {method => 'POST'});
    $tl_mapper->connect('/ack.json',
                        {method => '_handle_tl_ack'}, {method => 'POST'});
    $tl_mapper->connect('/updates/unacked_counts.json',
                        {method => '_handle_tl_get_unacked_counts'}, {method => 'GET'});
    $tl_mapper->connect($_, {method => '_handle_tl_index'}) foreach "", qw(/ /index.html /index.htm);
    $self->{router}->connect('/updates/unacked_counts.json',
                             {method => '_handle_get_unacked_counts'}, {method => 'GET'});
}

sub _get_timeline {
    my ($self, $dest) = @_;
    my $timeline = $self->{main_obj}->get_timeline($dest->{timeline});
    if(!defined($timeline)) {
        die qq{No timeline named $dest->{timeline}};
    }
    return $timeline;
}

sub _template_response {
    my ($self, %args) = @_;
    my $template_name = delete $args{template};
    croak 'template arg is mandatory' if not defined $template_name;
    my $args = delete $args{args};
    my $code = delete $args{code} || 200;
    my $headers = delete $args{headers} || [];
    if(!Plack::Util::header_exists($headers, 'Content-Type')) {
        push(@$headers, 'Content-Type', 'text/html; charset=utf8');
    }
    my $ret = Encode::encode('utf8', $self->{renderer}->render($template_name, $args));
    return [$code, $headers, [$ret]];
}

sub _notfound_response {
    my ($message) = @_;
    $message ||= 'Not Found';
    return ['404',
            ['Content-Type' => 'text/plain',
             'Content-Length' => length($message)],
            [$message]];
}

sub _json_response {
    my ($res_code, %response_object) = @_;
    if($res_code eq '200' && !exists($response_object{error})) {
        $response_object{error} = undef;
    }
    my $message = try {
        to_json(\%response_object, {ascii => 1})
    }catch {
        undef
    };
    if(defined($message)) {
        return [
            $res_code, ['Content-Type' => 'application/json; charset=utf-8'],
            [$message]
        ];
    }else {
        return _json_response(500, error => "error while encoding to JSON.");
    }
}

my $REGEXP_HTTP_URL = qr{https?:\/\/[A-Za-z0-9~\/._!\?\&=\-%#\+:\;,\@\']+};

sub _escape_and_linkify {
    my ($text) = @_;
    my $result_text = "";
    my $remaining_index = 0;
    while($text =~ m/\G(.*?)($REGEXP_HTTP_URL)/sg) {
        my ($other_text, $url) = ($1, $2);
        $result_text .= Text::Xslate::html_escape($other_text);
        $result_text .= qq{<a href="$url">} . Text::Xslate::html_escape($url) . qq{</a>};
        $remaining_index = pos($text);
    }
    $result_text .= Text::Xslate::html_escape(substr($text, $remaining_index));
    return $result_text;
}

sub _format_status_html_destructive {
    my ($self, $status) = @_;
    if(!defined($status->{busybird}{level})) {
        $status->{busybird}{level} = 0;
    }
    if(defined($status->{text})) {
        $status->{text} = Text::Xslate::mark_raw(_escape_and_linkify($status->{text}));
    }
    return $self->{renderer}->render("status.tt", $status);
}

my %RESPONSE_FORMATTER_FOR_TL_GET_STATUSES = (
    html => sub {
        my ($self, $code, %response_object) = @_;
        if($code == 200) {
            my $result = "";
            foreach my $status (@{$response_object{statuses}}) {
                $result .= $self->_format_status_html_destructive($status);
            }
            $result = Encode::encode('utf8', $result);
            return [200, ['Content-Type', 'text/html; charset=utf8'], [$result]];
        }else {
            return $self->_template_response(
                template => 'error.tt', args => {error => $response_object{error}},
                code => $code
            );
        }
    },
    json => sub {
        my ($self, $code, %response_object) = @_;
        return _json_response($code, %response_object);
    },
);


#############################

sub _handle_tl_get_statuses {
    my ($self, $req, $dest) = @_;
    return sub {
        my $responder = shift;
        my $formatter = $RESPONSE_FORMATTER_FOR_TL_GET_STATUSES{$dest->{format}};
        try {
            my $timeline = $self->_get_timeline($dest);
            my $count = $req->query_parameters->{count} || 20;
            if(!defined($formatter)) {
                $formatter = $RESPONSE_FORMATTER_FOR_TL_GET_STATUSES{html};
                die "Unknown format: $dest->{format}";
            }
            if(!looks_like_number($count) || int($count) != $count) {
                die "count parameter must be an integer";
            }
            my $ack_state = $req->query_parameters->{ack_state} || 'any';
            my $max_id = $req->query_parameters->{max_id};
            $timeline->get_statuses(
                count => $count, ack_state => $ack_state, max_id => $max_id,
                callback => sub {
                    my ($error, $statuses) = @_;
                    if(defined $error) {
                        $responder->($formatter->($self, 500, error => "$error"));
                        return;
                    }
                    $responder->($formatter->($self, 200, statuses => $statuses));
                }
            );
        }catch {
            my $e = shift;
            $responder->($formatter->($self, 400, error => "$e"));
        };
    };
}

sub _handle_tl_post_statuses {
    my ($self, $req, $dest) = @_;
    return sub {
        my $responder = shift;
        try {
            my $timeline = $self->_get_timeline($dest);
            my $posted_obj = decode_json($req->content);
            if(ref($posted_obj) ne 'ARRAY') {
                $posted_obj = [$posted_obj];
            }
            $timeline->add_statuses(
                statuses => $posted_obj,
                callback => sub {
                    my ($error, $added_num) = @_;
                    if(defined $error) {
                        $responder->(_json_response(500, error => "$error"));
                        return;
                    }
                    $responder->(_json_response(200, count => $added_num + 0));
                }
            );
        } catch {
            my $e = shift;
            $responder->(_json_response(400, error => "$e"));
        };
    };
}

sub _handle_tl_ack {
    my ($self, $req, $dest) = @_;
    return sub {
        my $responder = shift;
        try {
            my $timeline = $self->_get_timeline($dest);
            my $max_id = undef;
            my $ids = undef;
            if($req->content) {
                my $body_obj = decode_json($req->content);
                if(ref($body_obj) ne 'HASH') {
                    die 'Response body must be an object.';
                }
                $max_id = $body_obj->{max_id};
                $ids = $body_obj->{ids};
            }
            $timeline->ack_statuses(
                max_id => $max_id, ids => $ids,
                callback => sub {
                    my ($error, $acked_num) = @_;
                    if(defined $error) {
                        $responder->(_json_response(500, error => "$error"));
                        return;
                    }
                    $responder->(_json_response(200, count => $acked_num + 0));
                }
            );
        }catch {
            my $e = shift;
            $responder->(_json_response(400, error => "$e"));
        };
    };
}

sub _handle_tl_get_unacked_counts {
    my ($self, $req, $dest) = @_;
    return sub {
        my $responder = shift;
        try {
            my $timeline = $self->_get_timeline($dest);
            my $query_params = $req->query_parameters;
            my %assumed = ();
            if(defined $query_params->{total}) {
                $assumed{total} = delete $query_params->{total};
            }
            foreach my $query_key (keys %$query_params) {
                next if !looks_like_number($query_key);
                next if int($query_key) != $query_key;
                $assumed{$query_key} = $query_params->{$query_key};
            }
            $timeline->watch_unacked_counts(assumed => \%assumed, callback => sub {
                my ($error, $w, $unacked_counts) = @_;
                $w->cancel();
                if(defined $error) {
                    $responder->(_json_response(500, error => "$error"));
                    return;
                }
                $responder->(_json_response(200, unacked_counts => $unacked_counts));
            });
        }catch {
            my $e = shift;
            $responder->(_json_response(400, error => "$e"));
        };
    };
}

sub _handle_get_unacked_counts {
    my ($self, $req, $dest) = @_;
    return sub {
        my $responder = shift;
        try {
            my $query_params = $req->query_parameters;
            my $level = $query_params->{level};
            if(not defined($level)) {
                $level = "total";
            }elsif($level ne 'total' && (!looks_like_number($level) || int($level) != $level)) {
                die "level parameter must be an integer";
            }
            my %assumed = ();
            foreach my $query_key (keys %$query_params) {
                next if substr($query_key, 0, 3) ne 'tl_';
                $assumed{substr($query_key, 3)} = $query_params->{$query_key};
            }
            $self->{main_obj}->watch_unacked_counts(level => $level, assumed => \%assumed, callback => sub {
                my ($error, $w, $tl_unacked_counts) = @_;
                $w->cancel();
                if(defined $error) {
                    $responder->(_json_response(500, error => "$error"));
                    return;
                }
                $responder->(_json_response(200, unacked_counts => $tl_unacked_counts));
            });
        }catch {
            my $e = shift;
            $responder->(_json_response(400, error => "$e"));
        };
    };
}

sub _handle_tl_index {
    my ($self, $req, $dest) = @_;
    my $timeline = try {
        $self->_get_timeline($dest);
    }catch {
        undef
    };
    return _notfound_response if not defined $timeline;
    return $self->_template_response(
        template => "timeline.tt",
        args => {
            timeline_name => $timeline->name,
            script_name => $req->script_name,
        }
    );
}

1;
