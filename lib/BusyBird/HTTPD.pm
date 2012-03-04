package BusyBird::HTTPD;
use strict;
use warnings;

use POE qw(Component::Server::TCP Filter::HTTPD);
use HTTP::Status;
use HTTP::Response;
use HTTP::Request;
use Encode;

use BusyBird::Log ('bblog');
use BusyBird::Output;
use BusyBird::Request;
use BusyBird::RequestListener;
use BusyBird::StaticContent;

my $g_httpd_self;
my %g_httpd_params = (
    bind_address => '127.0.0.1',
    bind_port    => 8888,
);

sub init {
    my ($class, $content_dir) = @_;
    $g_httpd_self = bless {
        'request_points' => {},
    }, $class;
    $g_httpd_self->_addListeners(BusyBird::StaticContent->new($content_dir));
}

sub config {
    my ($class, %params) = @_;
    while(my ($key, $val) = each(%params)) {
        $g_httpd_params{$key} = $val;
    }
}

sub registerOutputs {
    my ($class, @output_streams) = @_;
    $g_httpd_self->_addListeners(@output_streams);
}

sub start {
    my ($class) = @_;
    if(!defined($g_httpd_self)) {
        die 'Call init() before start()';
    }
    POE::Component::Server::TCP->new(
        Port => $g_httpd_params{bind_port},
        Address => $g_httpd_params{bind_address},
        ClientInputFilter  => "POE::Filter::HTTPD",
        ClientOutputFilter => "POE::Filter::Stream",
        ClientConnected => sub {
            &bblog("connected:    $_[HEAP]{remote_ip}:$_[HEAP]{remote_port}");
        },
        ClientDisconnected => sub {
            &bblog("disconnected: $_[HEAP]{remote_ip}:$_[HEAP]{remote_port}");
        },
        ClientError => sub {
            my ($syscall_name, $error_num, $error_str) = @_[ARG0..ARG2];
            # Handle the client error here.
            &bblog("Custom ClientError: $syscall_name: $error_num: $error_str");
        },
        ClientInput => \&_handlerClientInput,
  );
}

sub replyPoint {
    my ($class_self, $point) = @_;
    my $self = ref($class_self) ? $class_self : $g_httpd_self;
    if(!$self->_isPointDefined($point)) {
        return 0;
    }
    &bblog(">>> Now Pending");
    &bblog($self->_getPendingRequestsString());
    &bblog(">>> ");
    &bblog("Try to reply to $point...");
    my $listener = $self->{request_points}{$point}{listener};
    my @request_keys = keys %{$self->{request_points}{$point}{requests}};
    if(!@request_keys) {
        &bblog("No requests for $point");
        return 1;
    }
    foreach my $req_key (@request_keys) {
        my $bb_request = $self->{request_points}{$point}{requests}{$req_key};
        my ($ret_code, $content_ref, $mime) = $listener->reply($bb_request->getPoint, $bb_request->getDetail);
        if($ret_code == BusyBird::RequestListener->HOLD) {
            &bblog("Request for $point is made pending.");
            next;
        }
        
        my $response = HTTP::Response->new();
        if($ret_code == BusyBird::RequestListener->REPLIED) {
            $response->code(200);
            $response->message('OK');
            $response->header('Content-Type', $mime) if defined($mime);
            $response->content_ref($content_ref);
            &bblog("Request for $point handled.");
        }elsif($ret_code == BusyBird::RequestListener->NOT_FOUND) {
            &bblog("RequestListener for $point returns Not_Found.");
            $self->_setNotFound($response);
        }else {
            die "Unknown return code $ret_code from RequestListener";
        }
        $self->_sendHTTPResponse($bb_request->getClient, $response);
        delete $self->{request_points}{$point}{requests}{$req_key};
    }
    return 1;
}

sub _unescapeURI {
    my ($uri) = @_;
    $uri =~ s/\+/ /g;
    $uri =~ s/%[0-9a-fA-F][0-9a-fA-F]/pack("C", hex($1))/eg;
    return $uri;
}

sub _handlerClientInput {
    my ($request, $heap) = @_[ARG0, HEAP];
    &bblog("start client input: $_[HEAP]{remote_ip}:$_[HEAP]{remote_port}------");
    &bblog("URI: " . $request->uri);
    my ($req_host, $req_path) = ('', '');
    my %detail_params = ();
    if($request->uri =~ m|^https?://([^/]+)(.+?)$|) {
        $req_host = $1;
        $req_path = $2;
    }else {
        $req_path = $request->uri;
    }
    $req_path = lc($req_path);
    $req_path = '/' . $req_path if $req_path !~ m|^/|;
    if($req_path =~ m|^([^\?]+)\?(.+)$|) {
        $req_path = $1;
        my @param_pairs = split(/\&/, $2);
        foreach my $param_pair (@param_pairs) {
            next if $param_pair !~ /^([^=]+)=([^=+])$/;
            $detail_params{&_unescapeURI($1)} = &_unescapeURI($2);
        }
    }
    $req_path .= "index.html" if $req_path =~ m|/$|;
    &bblog("Requested path: $req_path");
    
    my $bb_request = BusyBird::Request->new($req_path, $heap->{client}, \%detail_params);
    if(!$g_httpd_self->_pushRequest($bb_request)) {
        &bblog("  The path $req_path is not a request_point. Send Not_Found");
        my $response = HTTP::Response->new();
        $g_httpd_self->_setNotFound($response);
        $g_httpd_self->_sendHTTPResponse($heap->{client}, $response);
        return;
    }
    $g_httpd_self->replyPoint($req_path);
    &bblog("End client input------------------------");
}

## sub _cathandler_static {
##     my ($self, $request, $content_path, $client) = @_;
##     my $response = HTTP::Response->new();
##     print STDERR "path> $content_path\n";
##     if(!defined($self->{contents}{$content_path})) {
##         $self->_setNotFound($response);
##         $self->_sendHTTPResponse($client, $response);
##         return;
##     }
##     my $path = $self->{content_dir}."/".$content_path;
##     my $mimetype = $self->_getMimeForFilePath($path);
##     print STDERR "MIME: $mimetype\n";
##     my $file = IO::File->new();
##     if(!$file->open($path, "r")) {
##         $self->_setNotFound($response);
##         $self->_sendHTTPResponse($client, $response);
##         return;
##     }
##     my $filedata = '';
##     {
##         local $/ = undef;
##         $filedata = $file->getline();
##     }
##     $file->close();
##     $response->push_header('Content-Type', $mimetype);
##     $response->content_ref(\$filedata);
##     ## print $response->content;
##     $response->code(RC_OK);
##     ## $response->decode();
##     $self->_sendHTTPResponse($client, $response);
##     return;
## }
## 
## sub _cathandler_notify {
##     my ($self, $request, $point, $client) = @_;
##     my $bb_request = BusyBird::Request->new($point, $client, '');
##     if(!$self->_pushRequest($bb_request)) {
##         my $response = HTTP::Response->new();
##         $self->_setNotFound($response);
##         $self->_sendHTTPResponse($client, $response);
##         return;
##     }
##     $self->replyPoint($point);
## }

sub _setNotFound {
    my ($class_self, $response) = @_;
    $response->code(404);
    $response->message('Not Found');
    $response->header('Content-Type', 'text/plain');
    $response->content('Not Found');
}

sub _sendHTTPResponse {
    my ($class_self, $client, $response) = @_;
    $response->header('Content-Length', length($response->content));
    $client->put('HTTP/1.1 ' . $response->status_line . "\r\n" . $response->headers_as_string("\r\n") . "\r\n");
    $client->put($response->content);
}

sub _addListeners {
    my ($self, @listeners) = @_;
    foreach my $listener (@listeners) {
        foreach my $point ($listener->getRequestPoints()) {
            $self->_addRequestPoint($point, $listener);
        }
    }
}

sub _addRequestPoint {
    my ($self, $point_name, $listener) = @_;
    if($self->_isPointDefined($point_name)) {
        die "Point $point_name is already defined.";
    }
    $self->{request_points}{$point_name} = {listener => $listener,
                                            requests => {}};
    &bblog("Register request point: $point_name");
}

sub _isPointDefined {
    my ($self, $point_name) = @_;
    return defined($self->{request_points}{$point_name});
}

sub _pushRequest {
    my ($self, $bb_request) = @_;
    my $point = $bb_request->getPoint();
    if(!$self->_isPointDefined($point)) {
        return 0;
    }
    $self->{request_points}{$point}{requests}{$bb_request->getID} = $bb_request;
}

sub _getPendingRequestsString {
    my ($self) = @_;
    my $ret = '';
    foreach my $point (keys %{$self->{request_points}}) {
        $ret .= "Point: $point\n";
        foreach my $request (values %{$self->{request_points}{$point}{requests}}) {
            $ret .= sprintf("  Request: ID = %s\n", $request->getID());
        }
    }
    return $ret;
}

1;
