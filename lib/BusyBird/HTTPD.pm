package BusyBird::HTTPD;
use strict;
use warnings;

use POE qw(Component::Server::TCP Filter::HTTPD);
## use POE::Component::Server::HTTP;
use HTTP::Status;
use HTTP::Response;
use HTTP::Request;
use File::MimeInfo;
use IO::File;

use Data::Dumper;

$| = 1;

my $self;
my $PATH_STATIC_BASE = '/static/';

sub RC_WAIT() { 0;} ## DUMMY

sub init() {
    my ($class, $content_dir) = @_;
    my @contents = qw(style.css CA3I0048.JPG photo.jpg photo.png small.gif small.png);
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

sub start() {
    my ($class) = @_;
    if(!defined($self)) {
        die 'Call init() before start()';
    }
    POE::Component::Server::TCP->new(
        Port => 8888,
        ClientInputFilter  => "POE::Filter::HTTPD",
        ClientOutputFilter => "POE::Filter::Stream",
        ClientConnected => sub {
            print STDERR "got a connection from $_[HEAP]{remote_ip}\n";
        },
        ClientInput => sub {
            my $client_input = $_[ARG0];
            
            ## return;
            ## print STDERR ("INPUT------\n" . $client_input . "\n");
            ## if($client_input) {
            ##     return;
            ## }
            print STDERR ("---- Create response\n");
            my $response = HTTP::Response->new();
            $self->_handlerStaticContent($client_input, $response);
            ## $_[HEAP]{client}->put('DATA');
            ## $_[HEAP]{client}->put(pack('C*', 255,255,255,255,255,255,255,255,));
            ## $_[HEAP]{client}->put("\r\n");
            ## my $ret_data = $response->as_string("\r\n");
            $response->header('Content-Length', length($response->content));
            $_[HEAP]{client}->put('HTTP/1.1 ' . $response->status_line . "\r\n" . $response->headers_as_string("\r\n") . "\r\n");
            $_[HEAP]{client}->put($response->content);
            
            ## ** Looks like combination of HTTP::Response and
            ## ** PoCo::Server::TCP corrupts $response->content if
            ## ** it's binary data such as an image file. So I decided
            ## ** to use POE::Filter::Stream (no-op filter) and to
            ## ** send HTTP response headers and content
            ## ** separately. Because they are sent by separate
            ## ** packets, it may be unefficient in terms of bandwidth
            ## ** usage, though.
            
            return;
            
            ## my $ret_data = $response->content;
            ## my $as_str = $response->as_string("\r\n");
            ## 
            ## print $as_str;
            ## print "----------------\n";
            ## $_[HEAP]{client}->put($as_str);
            ## $_[HEAP]{client}->put("-----------------\n");
            ## 
            ## print $ret_data;
            ## my @headers = (
            ##     'HTTP/1.1 200 OK',
            ##     'Content-Type: image/gif',
            ##     'Content-Length: ' . length($ret_data),
            ##     'Connection: Close',
            ##     '',
            ##     ''
            ##     );
            ## $_[HEAP]{client}->put(join("\r\n", @headers) . $ret_data);
            ## ## $_[HEAP]{client}->put($ret_data);
            ## ## $_[HEAP]{client}->put($response);
        },
  );
##     my $aliases = POE::Component::Server::HTTP->new(
##         Port => 8888,
##         ContentHandler => {
##             '/comet_sample' => \&_handlerCometSample,
##             '/' => \&_handlerIndex,
##             $PATH_STATIC_BASE => \&_handlerStaticContent,
##         },
##         Headers => { Server => 'My Server' },
##         );

## ** HTTPDを終了するにはshutdownイベントを送る必要がある。SIGINTをトラップしてshutdownに変換？
## ** 新着件数などのサーバからのpush性の強いデータはcomet的にデータを送るといいかも
## ** http://d.hatena.ne.jp/dayflower/20061116/1163663677
## ** でもここのサンプル、実際動かしてみると二つ以上のコネクションを同時に張ってくれないような…
}

sub _handlerSample() {
    my ($self, $client, $client_input) = @_;
    my $response = HTTP::Response->new();
    my $path = $self->{content_dir}."/small.gif";
    my $mimetype = mimetype($path);
    $mimetype = 'application/octet-stream' if !defined($mimetype);
    my $file = IO::File->new();
    if(!$file->open($path, "r")) {
        &_setNotFound($response);
        print STDERR ("3\n");
        return $response;
    }
    my $filedata = '';
    {
        local $/ = undef;
        $filedata = $file->getline();
    }
    $file->close();
    $response->header('Content-Type', $mimetype);
    $response->header('Content-Length', length($filedata));
    $response->content_ref(\$filedata);
    $response->code(200);
    return $response;
}

sub _handlerIndex() {
    my ($request, $response) = @_;
    $response->code(RC_OK);
    $response->content("You just fetched " . $request->uri . "\n");
    ## my $ret_str = $client_agent->getHTMLHead($DEFAULT_STREAM_NAME) . $client_agent->getHTMLStream($DEFAULT_STREAM_NAME)
    ##     . $client_agent->getHTMLFoot($DEFAULT_STREAM_NAME);
    ## $response->content(Encode::encode('utf8', $ret_str));
    return RC_OK;
}

sub _handlerCometSample() {
    my ($request, $response) = @_;
    ## $notify_responses{refaddr($response)} = $response;
    $request->headers->header(Connection => 'close');
    return RC_WAIT;
}

sub _setNotFound() {
    my ($response) = @_;
    $response->code(404);
    $response->message('Not Found');
    $response->content('Not Found');
}

sub _handlerStaticContent() {
    my ($self, $request, $response) = @_;
    print STDERR ("URI: " . $request->uri . "\n");
    my ($req_host, $req_path) = ('', '');
    if($request->uri =~ m|^https?://([^/]+)(.+?)$|) {
        $req_host = $1;
        $req_path = $2;
    }else {
        $req_path = $request->uri;
    }
    $req_path = '/' . $req_path if $req_path !~ m|^/|;
    
    if($req_path !~ m|^$PATH_STATIC_BASE(.*)$|) {
        &_setNotFound($response);
        print STDERR ("1\n");
        return RC_OK;
    }
    my $content_path = $1;
    print STDERR "path> $content_path\n";
    if(!defined($self->{contents}{$content_path})) {
        &_setNotFound($response);
        print STDERR ("2\n");
        return RC_OK;
    }
    my $path = $self->{content_dir}."/".$content_path;
    my $mimetype = mimetype($path);
    $mimetype = 'application/octet-stream' if !defined($mimetype);
    my $file = IO::File->new();
    if(!$file->open($path, "r")) {
        &_setNotFound($response);
        print STDERR ("3\n");
        return RC_OK;
    }
    my $filedata = '';
    {
        ## local $/ = undef;
        ## $filedata = $file->getline();
        while(my $line = $file->getline()) {
            $filedata .= $line;
        }
        print STDERR "Write to stdout\n";
    }
    $file->close();
    $response->push_header('Content-Type', $mimetype);
    $response->content_ref(\$filedata);
    ## print $response->content;
    $response->code(RC_OK);
    ## $response->decode();
    return RC_OK;
}

1;
