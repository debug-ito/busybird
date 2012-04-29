package BusyBird::HTTPD;
use strict;
use warnings;

use AnyEvent;
use BusyBird::Log ('bblog');
use BusyBird::HTTPD::PathMatcher;

use Twiggy::Server;
use Plack::Builder;


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
        enable "Plack::Middleware::Static", path => qr{^/static/}, root => $g_httpd_params{static_root};
        $self->_createApp();
    });
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

sub _createApp {
    my ($self) = @_;
    return sub {
        my ($env) = @_;
        my $result = "It works!\n";
        return [
            '200',
            ['Content-Type' => 'text/plain',
             'Content-Length' => length($result)],
            [$result],
        ];
    };
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

