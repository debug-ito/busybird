package BusyBird::HTTPD;
use strict;

use POE;
use POE::Component::Server::HTTP;
use HTTP::Status;
use File::MimeInfo;
use IO::File;

my $self;
my $PATH_STATIC_BASE = '/static/';

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
    my $aliases = POE::Component::Server::HTTP->new(
        Port => 8888,
        ContentHandler => {
            '/comet_sample' => \&_handlerCometSample,
            '/' => \&_handlerIndex,
            $PATH_STATIC_BASE => \&_handlerStaticContent,
        },
        Headers => { Server => 'My Server' },
        );
## HTTPDを終了するにはshutdownイベントを送る必要がある。SIGINTをトラップしてshutdownに変換？

## 新着件数などのサーバからのpush性の強いデータはcomet的にデータを送るといいかも
## http://d.hatena.ne.jp/dayflower/20061116/1163663677
## でもここのサンプル、実際動かしてみると二つ以上のコネクションを同時に張ってくれないような…
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
    my ($request, $response) = @_;
    print STDERR ("URI: " . $request->uri . "\n");
    if($request->uri !~ m|^https?://[^/]+$PATH_STATIC_BASE(.*)$|) {
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
    $| = 1;
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
