package BusyBird::HTTPD;
use strict;
use warnings;

use POE qw(Component::Server::TCP Filter::HTTPD);
use HTTP::Status;
use HTTP::Response;
use HTTP::Request;
use File::MimeInfo;
use IO::File;

## use Data::Dumper;

my $self;
my $CAT_STATIC = 'static';
my $HANDLER_PREFIX = '_cathandler_';
my %MIME_MAP = (
    html => 'text/html',
    txt => 'text/plain',
    js => 'text/javascript',
    css => 'text/css',
    );

## sub RC_WAIT { 0;} ## DUMMY

sub init {
    my ($class, $content_dir) = @_;
    my @contents = qw(style.css index.html jquery.js shaper.js favicon.ico);
    $content_dir =~ s|/+$||g;
    $self = {
        'content_dir' => $content_dir,
        'contents' => {},
    };
    foreach my $file (@contents) {
        $self->{contents}{$file} = 1;
    }
    bless $self, $class;
}

sub start {
    my ($class) = @_;
    if(!defined($self)) {
        die 'Call init() before start()';
    }
    POE::Component::Server::TCP->new(
        Port => 8888,
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

    my $response = HTTP::Response->new();
    my $handler_name = $HANDLER_PREFIX . $category;
    if($self->can($handler_name)) {
        $self->$handler_name($request, $response, $lower_path);
    }else {
        print STDERR "No Category handler defined.\n";
        $self->_setNotFound($response);
    }
    $response->header('Content-Length', length($response->content));
    $heap->{client}->put('HTTP/1.1 ' . $response->status_line . "\r\n" . $response->headers_as_string("\r\n") . "\r\n");
    $heap->{client}->put($response->content);
    print STDERR "End client input------------------------\n";
}

sub _cathandler_static {
    my ($self, $request, $response, $content_path) = @_;
    print STDERR "path> $content_path\n";
    if(!defined($self->{contents}{$content_path})) {
        $self->_setNotFound($response);
        print STDERR ("2\n");
        return;
    }
    my $path = $self->{content_dir}."/".$content_path;
    my $mimetype = $self->_getMimeForFilePath($path);
    print STDERR "MIME: $mimetype\n";
    my $file = IO::File->new();
    if(!$file->open($path, "r")) {
        $self->_setNotFound($response);
        print STDERR ("3\n");
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
    return;
}

sub _setNotFound {
    my ($class, $response) = @_;
    $response->code(404);
    $response->message('Not Found');
    $response->content('Not Found');
}

sub _getMimeForFilePath {
    my ($class, $path) = @_;
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

## sub _handlerSample {
##     my ($self, $client, $client_input) = @_;
##     my $response = HTTP::Response->new();
##     my $path = $self->{content_dir}."/small.gif";
##     my $mimetype = mimetype($path);
##     $mimetype = 'application/octet-stream' if !defined($mimetype);
##     my $file = IO::File->new();
##     if(!$file->open($path, "r")) {
##         &_setNotFound($response);
##         print STDERR ("3\n");
##         return $response;
##     }
##     my $filedata = '';
##     {
##         local $/ = undef;
##         $filedata = $file->getline();
##     }
##     $file->close();
##     $response->header('Content-Type', $mimetype);
##     $response->header('Content-Length', length($filedata));
##     $response->content_ref(\$filedata);
##     $response->code(200);
##     return $response;
## }
## 
## sub _handlerIndex {
##     my ($request, $response) = @_;
##     $response->code(RC_OK);
##     $response->content("You just fetched " . $request->uri . "\n");
##     ## my $ret_str = $client_agent->getHTMLHead($DEFAULT_STREAM_NAME) . $client_agent->getHTMLStream($DEFAULT_STREAM_NAME)
##     ##     . $client_agent->getHTMLFoot($DEFAULT_STREAM_NAME);
##     ## $response->content(Encode::encode('utf8', $ret_str));
##     return RC_OK;
## }
## 
## sub _handlerCometSample {
##     my ($request, $response) = @_;
##     ## $notify_responses{refaddr($response)} = $response;
##     $request->headers->header(Connection => 'close');
##     return RC_WAIT;
## }
## 
## sub _handlerStaticContent {
##     my ($self, $request, $response) = @_;
##     print STDERR ("URI: " . $request->uri . "\n");
##     my ($req_host, $req_path) = ('', '');
##     if($request->uri =~ m|^https?://([^/]+)(.+?)$|) {
##         $req_host = $1;
##         $req_path = $2;
##     }else {
##         $req_path = $request->uri;
##     }
##     $req_path = '/' . $req_path if $req_path !~ m|^/|;
##     
##     if($req_path !~ m|^$PATH_STATIC_BASE(.*)$|) {
##         &_setNotFound($response);
##         print STDERR ("1\n");
##         return RC_OK;
##     }
##     my $content_path = $1;
##     print STDERR "path> $content_path\n";
##     if(!defined($self->{contents}{$content_path})) {
##         &_setNotFound($response);
##         print STDERR ("2\n");
##         return RC_OK;
##     }
##     my $path = $self->{content_dir}."/".$content_path;
##     my $mimetype = mimetype($path);
##     $mimetype = 'application/octet-stream' if !defined($mimetype);
##     my $file = IO::File->new();
##     if(!$file->open($path, "r")) {
##         &_setNotFound($response);
##         print STDERR ("3\n");
##         return RC_OK;
##     }
##     my $filedata = '';
##     {
##         ## local $/ = undef;
##         ## $filedata = $file->getline();
##         while(my $line = $file->getline()) {
##             $filedata .= $line;
##         }
##         print STDERR "Write to stdout\n";
##     }
##     $file->close();
##     $response->push_header('Content-Type', $mimetype);
##     $response->content_ref(\$filedata);
##     ## print $response->content;
##     $response->code(RC_OK);
##     ## $response->decode();
##     return RC_OK;
## }

1;
