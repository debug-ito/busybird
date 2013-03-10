package BusyBird::Main::PSGI;
use strict;
use warnings;
use BusyBird::Util qw(set_param);
use Router::Simple;
use Plack::Request;
use Plack::Builder ();
use Try::Tiny;
use JSON qw(decode_json encode_json to_json);
use Scalar::Util qw(looks_like_number);
use Carp;

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
    $tl_mapper->connect('/updates/unacked_counts.json',
                        {method => '_handle_tl_get_unacked_counts'}, {method => 'GET'});
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

sub _handle_tl_get_statuses {
    my ($self, $req, $dest) = @_;
    return sub {
        my $responder = shift;
        try {
            my $timeline = $self->_get_timeline($dest);
            my $count = $req->query_parameters->{count} || 20;
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
                        $responder->(_json_response(500, error => "$error"));
                        return;
                    }
                    $responder->(_json_response(200, statuses => $statuses));
                }
            );
        }catch {
            my $e = shift;
            $responder->(_json_response(400, error => "$e"));
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
            if($req->content) {
                my $body_obj = decode_json($req->content);
                $max_id = $body_obj->{max_id};
            }
            $timeline->ack_statuses(
                max_id => $max_id,
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

1;

