package BusyBird::Main::PSGI;
use strict;
use warnings;
use BusyBird::Util qw(set_param);
use BusyBird::Main::PSGI::View;
use Router::Simple;
use Plack::Request;
use Plack::Builder ();
use Plack::App::File;
use Try::Tiny;
use JSON qw(decode_json);
use Scalar::Util qw(looks_like_number);
use Carp;
use Exporter qw(import);
use URI::Escape qw(uri_unescape);

our @EXPORT = our @EXPORT_OK = qw(create_psgi_app);

sub create_psgi_app {
    my ($main_obj) = @_;
    my @timelines = $main_obj->get_all_timelines();
    if(!@timelines) {
        $main_obj->timeline('home');
    }
    my $self = __PACKAGE__->_new(main_obj => $main_obj);
    return $self->_to_app;
}

sub _new {
    my ($class, %params) = @_;
    my $self = bless {
        router => Router::Simple->new,
        view => undef,
    }, $class;
    $self->set_param(\%params, "main_obj", undef, 1);
    $self->{view} = BusyBird::Main::PSGI::View->new(main_obj => $self->{main_obj});
    $self->_build_routes();
    return $self;
}

sub _to_app {
    my $self = shift;
    my $sharedir = $self->{main_obj}->get_config("sharedir_path");
    $sharedir =~ s{/+$}{};
    return Plack::Builder::builder {
        Plack::Builder::enable 'ContentLength';
        Plack::Builder::mount '/static' => Plack::App::File->new(
            root => File::Spec->catdir($sharedir, 'www', 'static')
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
            return $self->{view}->response_notfound();
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

sub _get_timeline_name {
    my ($dest) = @_;
    my $name = $dest->{timeline};
    $name = "" if not defined($name);
    $name =~ s/\+/ /g;
    return uri_unescape($name);
}

sub _get_timeline {
    my ($self, $dest) = @_;
    my $name = _get_timeline_name($dest);
    my $timeline = $self->{main_obj}->get_timeline($name);
    if(!defined($timeline)) {
        die qq{No timeline named $name};
    }
    return $timeline;
}

sub _handle_tl_get_statuses {
    my ($self, $req, $dest) = @_;
    return sub {
        my $responder = shift;
        try {
            my $timeline = $self->_get_timeline($dest);
            my $count = $req->query_parameters->{count} || 20;
            if(!defined($dest->{format})) {
                $dest->{format} = "";
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
                        $responder->($self->{view}->response_statuses(
                            error => "$error", http_code => 500, format => $dest->{format},
                            timeline_name => $timeline->name
                        ));
                        return;
                    }
                    $responder->($self->{view}->response_statuses(
                        statuses => $statuses, http_code => 200, format => $dest->{format},
                        timeline_name => $timeline->name
                    ));
                }
            );
        }catch {
            my $e = shift;
            $responder->($self->{view}->response_statuses(
                error => "$e", http_code => 400, format => $dest->{format},
            ));
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
                        $responder->($self->{view}->response_json(500, {error => "$error"}));
                        return;
                    }
                    $responder->($self->{view}->response_json(200, {count => $added_num + 0}));
                }
            );
        } catch {
            my $e = shift;
            $responder->($self->{view}->response_json(400, {error => "$e"}));
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
                        $responder->($self->{view}->response_json(500, {error => "$error"}));
                        return;
                    }
                    $responder->($self->{view}->response_json(200, {count => $acked_num + 0}));
                }
            );
        }catch {
            my $e = shift;
            $responder->($self->{view}->response_json(400, {error => "$e"}));
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
                    $responder->($self->{view}->response_json(500, {error => "$error"}));
                    return;
                }
                $responder->($self->{view}->response_json(200, {unacked_counts => $unacked_counts}));
            });
        }catch {
            my $e = shift;
            $responder->($self->{view}->response_json(400, {error => "$e"}));
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
                    $responder->($self->{view}->response_json(500, {error => "$error"}));
                    return;
                }
                $responder->($self->{view}->response_json(200, {unacked_counts => $tl_unacked_counts}));
            });
        }catch {
            my $e = shift;
            $responder->($self->{view}->response_json(400, {error => "$e"}));
        };
    };
}

sub _handle_tl_index {
    my ($self, $req, $dest) = @_;
    return $self->{view}->response_timeline(_get_timeline_name($dest), $req->script_name);
}

1;


__END__

=pod

=head1 NAME

BusyBird::Main::PSGI - PSGI controller for BusyBird::Main

=head1 SYNOPSIS

    use BusyBird::Main;
    use BusyBird::Main::PSGI;
    
    my $main = BusyBird::Main->new();
    my $psgi_app = create_psgi_app($main);

=head1 DESCRIPTION

This is the controller object for L<BusyBird::Main>.
It creates a L<PSGI> application from a L<BusyBird::Main> object.

=head1 EXPORTED FUNCTIONS

The following functions are exported by default.

=head2 $psgi_app = create_psgi_app($main_obj)

Creates a L<PSGI> application object.

C<$main_obj> is a L<BusyBird::Main> object.
If there is no timeline in the C<$main_obj>, it creates C<"home"> timeline.

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut
