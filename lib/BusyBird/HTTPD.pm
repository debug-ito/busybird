package BusyBird::HTTPD;
use strict;
use warnings;

use AnyEvent;
use BusyBird::Log ('bblog');
use BusyBird::HTTPD::PathMatcher;

use Twiggy::Server;
use Plack::Builder;
use Plack::Request;


my $g_httpd_self = undef;
my %g_httpd_params = (
    bind_address => '127.0.0.1',
    bind_port    => 8888,
    static_root  => './resources/httpd/',
);

sub init {
    my ($class) = @_;
    $g_httpd_self = bless {
        backend => undef,
        request_points => {},
    }, $class;
}

sub config {
    my ($class, %params) = @_;
    while(my ($key, $val) = each(%params)) {
        $g_httpd_params{$key} = $val;
    }
}

sub start {
    my ($class) = @_;
    if(!defined($g_httpd_self)) {
        die 'Call init() before start()';
    }
    my $self = $g_httpd_self;
    $self->{backend} = Twiggy::Server->new(
        host => $g_httpd_params{bind_address},
        port => $g_httpd_params{bind_port},
    );
    $self->{backend}->register_service(builder {
        enable "Plack::Middleware::ContentLength";
        enable "Plack::Middleware::Static", path => qr{^/static/}, root => $g_httpd_params{static_root};
        $self->_createApp();
    });
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
        die "Cannot create PathMatcher from matcher_obj $matcher_obj.";
        return 0;
    }
    my $pointkey = $matcher->toString();
    if(defined($self->{request_points}->{$pointkey})) {
        die "request_point key $pointkey is already defined";
        return 0;
    }
    $self->{request_points}->{$pointkey} = {
        matcher => $matcher,
        listener => $listener_coderef,
    };
    return 1;
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

## sub _addListeners {
##     my ($self, @listeners) = @_;
##     foreach my $listener (@listeners) {
##         foreach my $point ($listener->getRequestPoints()) {
##             $self->_addRequestPoint($point, $listener);
##         }
##     }
## }
## 
## sub _addRequestPoint {
##     my ($self, $point_name, $listener) = @_;
##     if($self->_isPointDefined($point_name)) {
##         die "Point $point_name is already defined.";
##     }
##     $self->{request_points}{$point_name} = {listener => $listener,
##                                             requests => {}};
##     &bblog("Register request point: $point_name");
## }

1;

