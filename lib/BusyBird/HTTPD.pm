package BusyBird::HTTPD;
use strict;
use warnings;

use Carp;
use AnyEvent;
use BusyBird::Log ('bblog');
use BusyBird::HTTPD::PathMatcher;
use BusyBird::HTTPD::Helper qw(httpResSimple);
use BusyBird::Output;

use Twiggy::Server;
use Plack::Builder;
use Plack::Request;


my $g_httpd_self = undef;

sub init {
    my ($class) = @_;
    $g_httpd_self = bless {
        backend => undef,
        request_points => {},
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
    my $app = builder {
        enable "Plack::Middleware::ContentLength";
        enable "Plack::Middleware::Static", path => qr{^/static/}, root => $params{static_root} || './resources/httpd/';
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
                        my $statuses = $res{new_statuses};
                        my $ret = BusyBird::Status->format($req->env->{'busybird.format'}, $statuses);
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
            my %S = (
                global_header_height => '50px',
                global_side_height => '200px',
                side_width => '150px',
                optional_width => '100px',
                profile_image_section_width => '50px',
            );
            my $name = $output->getName();
            my $page = <<"END";
<html>
  <head>
    <title>$name - BusyBird</title>
    <meta content='text/html; charset=UTF-8' http-equiv='Content-Type'/>
    <link rel="stylesheet" href="/static/style.css" type="text/css" media="screen" />
    <style type="text/css"><!--

div#global_header {
    height: $S{global_header_height};
}

div#global_side {
    top: $S{global_header_height};
    width: $S{side_width};
    height: $S{global_side_height};
}

div#side_container {
    width: $S{side_width};
    margin: $S{global_side_height} 0 0 0;
}

div#main_container {
    margin: $S{global_header_height} $S{optional_width} 0 $S{side_width};
}

div#optional_container {
    width: $S{optional_width};
}

div.status_profile_image {
    width: $S{profile_image_section_width};
}

div.status_main {
    margin: 0 0 0 $S{profile_image_section_width};
}

    --></style>
    <script type="text/javascript" src="/static/jquery.js"></script>
    <script type="text/javascript"><!--
    function bbGetOutputName() {return "$name"}
--></script>
    <script type="text/javascript" src="/static/main.js"></script>
  </head>
  <body>
    <div id="global_header">
    </div>
    <div id="global_side">
    </div>
    <div id="side_container">
    </div>
    <div id="optional_container">
    </div>
    <div id="main_container">
      <ul id="statuses">
      </ul>
      <div id="main_footer">
        <button id="more_button" type="button" onclick="" >More...</button>
      </div>
    </div>
  </body>
</html>
END
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
                return $request_point->{listener}->(Plack::Request->new($env));
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

