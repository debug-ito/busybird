package BusyBird::Main::PSGI;
use strict;
use warnings;
use BusyBird::Util qw(set_param);
use Router::Simple;
use Plack::Request;
use Plack::Builder ();
use Try::Tiny;
use JSON qw(decode_json encode_json);
use Scalar::Util qw(looks_like_number);

sub create_psgi_app {
    my ($class, $main_obj) = @_;
    my $self = $class->_new(main_obj => $main_obj);
    return $self->_to_app;
}

sub _new {
    my ($class, %params) = @_;
    my $self = bless {
        router => Router::Simple->new,
    }, $class;
    $self->set_param(\%params, "main_obj", undef, 1);
    $self->_build_routes();
    return $self;
}

sub _to_app {
    my $self = shift;
    return Plack::Builder::builder {
        Plack::Builder::enable 'ContentLength';
        $self->_my_app;
    };
}

sub _my_app {
    my ($self) = @_;
    return sub {
        my ($env) = @_;
        if(my $dest = $self->{router}->match($env)) {
            my $method = $dest->{method};
            my $req = Plack::Request->new($env);
            return $self->$method($req, $dest);
        }else {
            my $message = 'Not Found';
            return ['404',
                    ['Content-Type' => 'text/plain',
                     'Content-Length' => length($message)],
                    [$message]];
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
}

sub _get_timeline {
    my ($self, $dest) = @_;
    my $timeline = $self->{main_obj}->get_timeline($dest->{timeline});
    if(!defined($timeline)) {
        die qq{No timeline named $dest->{timeline}};
    }
    return $timeline;
}

sub _json_bool {
    my ($val) = @_;
    return $val ? JSON::true : JSON::false;
}

sub _json_response {
    my ($res_code, $success, %other_params) = @_;
    my $obj = {is_success => _json_bool($success), %other_params};
    my $message = try {
        encode_json($obj)
    }catch {
        undef
    };
    if(defined($message)) {
        return [
            $res_code, ['Content-Type' => 'application/json; charset=utf-8'],
            [$message]
        ];
    }else {
        return _json_response(500, 0, error => "error while encoding to JSON.");
    }
}

sub _handle_tl_get_statuses {
    my ($self, $req, $dest) = @_;
    return sub {
        my $responder = shift;
        try {
            my $timeline = $self->_get_timeline($dest);
            my $count = $req->query_parameters->{count} || 20;
            if(!looks_like_number($count)) {
                die "count parameter must be an integer";
            }
            my $ack_state = $req->query_parameters->{ack_state} || 'any';
            my $max_id = $req->query_parameters->{max_id};
            $timeline->get_statuses(
                count => $count, ack_state => $ack_state, max_id => $max_id,
                callback => sub {
                    my ($statuses, $error) = @_;
                    if(int(@_) >= 2) {
                        $responder->(_json_response(500, 0, error => "$error"));
                        return;
                    }
                    $responder->(_json_response(200, 1, statuses => $statuses));
                }
            );
        }catch {
            my $e = shift;
            $responder->(_json_response(400, 0, error => "$e"));
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
                    my ($added_num, $error) = @_;
                    if(int(@_) >= 2) {
                        $responder->(_json_response(500, 0, error => "$error"));
                        return;
                    }
                    $responder->(_json_response(200, 1, count => $added_num + 0));
                }
            );
        } catch {
            my $e = shift;
            $responder->(_json_response(400, 0, error => "$e"));
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
            if($req->content) {
                my $body_obj = decode_json($req->content);
                $max_id = $body_obj->{max_id};
            }
            $timeline->ack_statuses(
                max_id => $max_id,
                callback => sub {
                    my ($acked_num, $error) = @_;
                    if(int(@_) >= 2) {
                        $responder->(_json_response(500, 0, error => "$error"));
                        return;
                    }
                    $responder->(_json_response(200, 1, count => $acked_num + 0));
                }
            );
        }catch {
            my $e = shift;
            $responder->(_json_response(400, 0, error => "$e"));
        };
    };
}

1;

