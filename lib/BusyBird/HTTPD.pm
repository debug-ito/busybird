package BusyBird::HTTPD;
use strict;
use warnings;
use constant DEFAULT_DOCUMENT_ROOT => './resources/httpd';

use Carp;
use AnyEvent;
use BusyBird::Log ('bblog');
use BusyBird::HTTPD::PathMatcher;
use BusyBird::HTTPD::Helper qw(httpResSimple);
use BusyBird::Output;
use BusyBird::Status::Buffer;

use Twiggy::Server;
use Plack::Builder;
use Plack::Request;
use Text::MicroTemplate::Extended;


my $g_httpd_self = undef;

sub init {
    my ($class) = @_;
    $g_httpd_self = bless {
        backend => undef,
        request_points => {},
        template_engine => undef,
    }, $class;
}

$g_httpd_self = __PACKAGE__->init();

sub start {
    my ($class, %params) = @_;
    if(!defined($g_httpd_self)) {
        croak 'Call init() before start()';
    }
    my $self = $g_httpd_self;
    $self->{backend} = Twiggy::Server->new(
        host => $params{bind_address} || '127.0.0.1',
        port => $params{bind_port} || 8888,
    );
    $params{document_root} ||= DEFAULT_DOCUMENT_ROOT;
    $params{document_root} =~ s!/+$!!;
    $self->{template_engine} = Text::MicroTemplate::Extended->new(
        include_path => ["$params{document_root}/templates"]
    );
    my $app = builder {
        enable "Plack::Middleware::ContentLength";
        enable "Plack::Middleware::Static", path => qr{^/static/}, root => $params{document_root};
        $self->_createApp()
    };
    if(defined($params{customize})) {
        $app = $params{customize}->($app);
    }
    $self->{backend}->register_service($app);
}

sub addRequestPoints {
    my ($class_self, @points_array) = @_;
    foreach my $point_entry (@points_array) {
        $class_self->addRequestPoint(@$point_entry);
    }
}

sub addRequestPoint {
    my ($class_self, $matcher_obj, $listener_coderef) = @_;
    my $self = ref($class_self) ? $class_self : $g_httpd_self;
    my $matcher = BusyBird::HTTPD::PathMatcher->new($matcher_obj);
    if(!defined($matcher)) {
        croak "Cannot create PathMatcher from matcher_obj $matcher_obj.";
        return 0;
    }
    my $pointkey = $matcher->toString();
    if(defined($self->{request_points}->{$pointkey})) {
        croak "request_point key $pointkey is already defined";
        return 0;
    }
    $self->{request_points}->{$pointkey} = {
        matcher => $matcher,
        listener => $listener_coderef,
    };
    return 1;
}

sub addOutput {
    my ($class_self, $output) = @_;
    my $self = ref($class_self) ? $class_self : $g_httpd_self;
    $self->addRequestPoint(
        '/' . $output->getName() . '/new_statuses', sub {
            my ($req) = @_;
            return sub {
                my $responder = shift;
                $output->select(
                    sub {
                        my ($id, %res) = @_;
                        my $status_buffer = $res{new_statuses};
                        my $ret = BusyBird::Status->format($req->env->{'busybird.format'}, $status_buffer->get);
                        if(defined($ret)) {
                            $responder->(httpResSimple(
                                200, \$ret, BusyBird::Status->mime($req->env->{'busybird.format'})
                            ));
                        }else {
                            $responder->(httpResSimple(
                                400, 'Unsupported format.'
                            ));
                        }
                        return 1;
                    },
                    new_statuses => 0,
                );
            };
        }
    );
    $self->addRequestPoint(
        '/' . $output->getName() . '/all_statuses', sub {
            my ($request) = @_;
            my $detail = $request->parameters;
            my $statuses = $output->getPagedStatuses(%$detail);
            my $ret = BusyBird::Status->format($request->env->{'busybird.format'}, $statuses);
            if(!defined($ret)) {
                return httpResSimple(400, 'Unsupported format');
            }
            return httpResSimple(200, \$ret, BusyBird::Status->mime($request->env->{'busybird.format'}));
        }
    );
    $self->addRequestPoint(
        '/' . $output->getName() . '/confirm', sub {
            $output->confirm();
            return httpResSimple(200, "Confirm OK");
        }
    );
    $self->addRequestPoint(
        '/' . $output->getName() . '/index', sub {
            my $page = $self->{template_engine}->render(
                'output',
                global_header_height => '50px',
                global_side_height => '200px',
                side_width => '150px',
                optional_width => '100px',
                profile_image_section_width => '50px',
                name => $output->getName(),
            );
            return httpResSimple(200, \$page, 'text/html');
        }
    );
}

sub _extractFormat {
    my ($self, $path) = @_;
    if($path =~ m{^(.*/[^\.]*)\.([^/]+)$}) {
        return ($1, $2);
    }else {
        return ($path, "");
    }
}

sub _createApp {
    my ($self) = @_;
    return sub {
        my ($env) = @_;
        if(substr($env->{PATH_INFO}, -1) eq '/') {
            $env->{PATH_INFO} .= 'index.html';
        }
        @$env{'busybird.pathbody', 'busybird.format'} = $self->_extractFormat($env->{PATH_INFO});
        foreach my $request_point (values %{$self->{request_points}}) {
            my @matched = $request_point->{matcher}->match($env->{'busybird.pathbody'});
            if(@matched) {
                $env->{'busybird.matched'} = \@matched;
                my $result = undef;
                eval {
                    $result = $request_point->{listener}->(Plack::Request->new($env));
                };
                if($@) {
                    my $error = "$@";
                    return [
                        '500',
                        ['Content-Type' => 'text/plain', 'Content-Length' => length($error)],
                        ["Error:\n", $error]
                    ];
                }
                return $result;
            }
        }
        my $result = sprintf("Not Found: path %s", $env->{PATH_INFO});
        return [
            '404',
            ['Content-Type' => 'text/plain',
             'Content-Length' => length($result)],
            [$result],
        ];
    };
}

sub instance {
    return $g_httpd_self;
}

1;

