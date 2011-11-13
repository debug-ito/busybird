package BusyBird::HTTPD;
use strict;
use warnings;

use POE qw(Component::Server::TCP Filter::HTTPD);
use HTTP::Status;
use HTTP::Response;
use HTTP::Request;
use File::MimeInfo;
use IO::File;
use Encode;

use BusyBird::Output;
use BusyBird::Request;

## use Data::Dumper;

my $g_httpd_self;
my $CAT_STATIC = 'static';
my $HANDLER_PREFIX = '_cathandler_';
my %MIME_MAP = (
    html => 'text/html',
    txt => 'text/plain',
    js => 'text/javascript',
    css => 'text/css',
    );

my $LISTEN_PORT = 8888;
my @NOTIFY_FOR_OUTPUT = qw(new_statuses);


sub init {
    my ($class, $content_dir) = @_;
    my @contents = qw(style.css index.html jquery.js shaper.js favicon.ico);
    $content_dir =~ s|/+$||g;
    $g_httpd_self = {
        'content_dir' => $content_dir,
        'contents' => {},
        'notify_points' => {},
    };
    foreach my $file (@contents) {
        $g_httpd_self->{contents}{$file} = 1;
    }
    bless $g_httpd_self, $class;
}

sub registerOutputs {
    my ($class, @output_streams) = @_;
    foreach my $output_stream (@output_streams) {
        foreach my $notify_event (@NOTIFY_FOR_OUTPUT) {
            my $point_name = $notify_event . '/' . $output_stream->getName();
            $g_httpd_self->{notify_points}{$point_name} = {listener => $output_stream, requests => {}};
            print STDERR "Register notify point: $point_name\n";
        }
    }
}

sub start {
    my ($class) = @_;
    if(!defined($g_httpd_self)) {
        die 'Call init() before start()';
    }
    POE::Component::Server::TCP->new(
        Port => $LISTEN_PORT,
        Address => '127.0.0.1',
        ClientInputFilter  => "POE::Filter::HTTPD",
        ClientOutputFilter => "POE::Filter::Stream",
        ClientConnected => sub {
            print STDERR "connected:    $_[HEAP]{remote_ip}:$_[HEAP]{remote_port}\n";
        },
        ClientDisconnected => sub {
            print STDERR "disconnected: $_[HEAP]{remote_ip}:$_[HEAP]{remote_port}\n";
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
    my $listener = $self->{notify_points}{$point}{listener};
    my @request_keys = keys %{$self->{notify_points}{$point}{requests}};
    foreach my $req_key (@request_keys) {
        my $bb_request = $self->{notify_points}{$point}{requests}{$req_key};
        my ($content, $mime) = $listener->reply($bb_request->getPoint, $bb_request->getDetail);
        if(defined($content)) {
            $mime = 'text/plain' if !defined($mime);
            my $response = HTTP::Response->new();
            $response->code(200);
            $response->header('Content-Type', $mime);
            $response->content(Encode::encode('utf8', $content));
            $self->_sendHTTPResponse($bb_request->getClient, $response);
            delete $self->{notify_points}{$point}{requests}{$req_key};
        }
    }
}

sub _handlerClientInput {
    my ($request, $heap) = @_[ARG0, HEAP];
    print STDERR "start client input: $_[HEAP]{remote_ip}:$_[HEAP]{remote_port}------\n";
    print STDERR ("URI: " . $request->uri . "\n");
    my ($req_host, $req_path) = ('', '');
    if($request->uri =~ m|^https?://([^/]+)(.+?)$|) {
        $req_host = $1;
        $req_path = $2;
    }else {
        $req_path = $request->uri;
    }
    $req_path = lc($req_path);
    $req_path = '/' . $req_path if $req_path !~ m|^/|;
    $req_path .= "index.html" if $req_path =~ m|/$|;
    my ($category, $lower_path);
    if($req_path =~ m|^/([^/]+)/(.+)$|) {
        ($category, $lower_path) = ($1, $2);
    }else {
        print STDERR "Invalid Path. Try static.\n";
        $req_path =~ m|^/+(.+?)$|;
        ($category, $lower_path) = ($CAT_STATIC, $1);
    }
    print STDERR "Category: $category, Lower_path: $lower_path\n";

    my $handler_name = $HANDLER_PREFIX . $category;
    if($g_httpd_self->can($handler_name)) {
        $g_httpd_self->$handler_name($request, $lower_path, $heap->{client});
    }else {
        print STDERR "No Category handler defined.\n";
        my $response = HTTP::Reponse->new();
        $g_httpd_self->_setNotFound($response);
        $g_httpd_self->_sendHTTPResponse($heap->{client}, $response);
    }
    
    print STDERR "End client input------------------------\n";
}

sub _cathandler_static {
    my ($self, $request, $content_path, $client) = @_;
    my $response = HTTP::Response->new();
    print STDERR "path> $content_path\n";
    if(!defined($self->{contents}{$content_path})) {
        $self->_setNotFound($response);
        $self->_sendHTTPResponse($client, $response);
        return;
    }
    my $path = $self->{content_dir}."/".$content_path;
    my $mimetype = $self->_getMimeForFilePath($path);
    print STDERR "MIME: $mimetype\n";
    my $file = IO::File->new();
    if(!$file->open($path, "r")) {
        $self->_setNotFound($response);
        $self->_sendHTTPResponse($client, $response);
        return;
    }
    my $filedata = '';
    {
        local $/ = undef;
        $filedata = $file->getline();
    }
    $file->close();
    $response->push_header('Content-Type', $mimetype);
    $response->content_ref(\$filedata);
    ## print $response->content;
    $response->code(RC_OK);
    ## $response->decode();
    $self->_sendHTTPResponse($client, $response);
    return;
}

sub _cathandler_notify {
    my ($self, $request, $point, $client) = @_;
    my $bb_request = BusyBird::Request->new($point, $client, '');
    if(!$self->_pushRequest($bb_request)) {
        my $response = HTTP::Response->new();
        $self->_setNotFound($response);
        $self->_sendHTTPResponse($client, $response);
        return;
    }
    $self->replyPoint($point);
}

sub _setNotFound {
    my ($class, $response) = @_;
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

sub _getMimeForFilePath {
    my ($class_self, $path) = @_;
    if($path =~ m|\.([^\.]+)$|) {
        my $ext = $1;
        $ext = lc($ext);
        if(defined($MIME_MAP{$ext})) {
            return $MIME_MAP{$ext};
        }
    }
    my $mimetype = mimetype($path);
    $mimetype = 'application/octet-stream' if !defined($mimetype);
    return $mimetype;
}

sub _isPointDefined {
    my ($self, $point_name) = @_;
    return defined($self->{notify_points}{$point_name});
}

sub _pushRequest {
    my ($self, $bb_request) = @_;
    my $point = $bb_request->getPoint();
    if(!$self->_isPointDefined($point)) {
        return 0;
    }
    $self->{notify_points}{$point}{requests}{$bb_request->getID} = $bb_request;
}

1;
