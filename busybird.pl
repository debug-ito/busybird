#!/usr/bin/perl -w
use strict;
use warnings;
use Scalar::Util qw(refaddr);
use Encode;

use POE;
use POE::Component::Server::HTTP;
use HTTP::Status;

use Net::Twitter;

use BusyBird::Input;
use BusyBird::Input::Twitter::HomeTimeline;
use BusyBird::Input::Twitter::List;
use BusyBird::Output;
use BusyBird::Judge;
use BusyBird::Timer;
use BusyBird::ClientAgent;

require 'config.test.pl';

my $TIMER_INTERVAL_MIN = 60;
my $DEFAULT_STREAM_NAME = 'default';

my %notify_responses = ();
my $client_agent = BusyBird::ClientAgent->new();

sub main() {
    my %configs = &tempGetConfig();
    my $nt = Net::Twitter->new(
        traits   => [qw/OAuth API::REST API::Lists/],
        consumer_key        => $configs{consumer_key},
        consumer_secret     => $configs{consumer_secret},
        access_token        => $configs{token},
        access_token_secret => $configs{token_secret},
        ssl => 1,
        );
    my $input  = BusyBird::Input::Twitter::List->new(name => 'list_test', nt => $nt, owner_name => $configs{owner_name}, list_slug_name => $configs{list_slug_name});
    my $output = BusyBird::Output->new($DEFAULT_STREAM_NAME);
    $output->judge(BusyBird::Judge->new());
    $output->agents($client_agent);
    ## ** タイマーを複数のInputで共有するのは危険。
    &initiateInputStream($input, BusyBird::Timer->new(120), $output);
    &initiateInputStream(
        BusyBird::Input::Twitter::HomeTimeline->new(name => 'home', nt => $nt),
        BusyBird::Timer->new(200),
        $output
        );

    my $aliases = POE::Component::Server::HTTP->new(
        Port => 8888,
        ContentHandler => {
            '/comet_sample' => \&poeCometSample,
            '/' => \&poeIndex,
        },
        Headers => { Server => 'My Server' },
        );
## HTTPDを終了するにはshutdownイベントを送る必要がある。SIGINTをトラップしてshutdownに変換？

## 新着件数などのサーバからのpush性の強いデータはcomet的にデータを送るといいかも
## http://d.hatena.ne.jp/dayflower/20061116/1163663677
## でもここのサンプル、実際動かしてみると二つ以上のコネクションを同時に張ってくれないような…

    POE::Kernel->run();
}

sub initiateInputStream() {
    my ($input_stream, $timer, @output_streams) = @_;
    POE::Session->create(
        heap => {
            input_stream => $input_stream,
            timer => $timer,
            output_streams => \@output_streams,
        },
        inline_states => {
            ## タイムライン名でaliasを設定するといいのかもしれない。
            _start => sub { $_[KERNEL]->yield("timer_fire") },
            set_delay => sub {
                my $delay = $_[HEAP]->{timer}->getNextDelay();
                printf STDERR ("INFO: Input %s will be checked in %.2f seconds.\n", $_[HEAP]->{input_stream}->getName(), $delay);
                $_[KERNEL]->delay('timer_fire', $delay);
            },
            timer_fire   => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                my $input = $heap->{input_stream};
                printf STDERR ("INFO: fire on input %s\n", $input->getName());
                
                my $statuses;
                eval {
                    $statuses = $input->getNewStatuses();
                };
                if($@) {
                    printf STDERR ("ERROR: while getting input %s: %s\n", $input->getName(), $@);
                    return $kernel->yield('set_delay');;
                }
                foreach my $output_stream (@{$heap->{output_streams}}) {
                    $output_stream->pushStatuses($statuses);
                }
                return $kernel->yield('set_delay');
            },
            change_interval => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                my $new_interval = ($_[ARG0] < $TIMER_INTERVAL_MIN ? $TIMER_INTERVAL_MIN : $_[ARG0]);
                $heap->{timer}->setInterval($new_interval);
                $kernel->yield('set_delay');
            },
        },
        );
}

sub poeIndex() {
    my ($request, $response) = @_;
    $response->code(RC_OK);
    my $ret_str = $client_agent->getHTMLHead($DEFAULT_STREAM_NAME) . $client_agent->getHTMLStream($DEFAULT_STREAM_NAME)
        . $client_agent->getHTMLFoot($DEFAULT_STREAM_NAME);
    $response->content(Encode::encode('utf8', $ret_str));
    return RC_OK;
}

sub poeCometSample() {
    my ($request, $response) = @_;
    $notify_responses{refaddr($response)} = $response;
    $request->headers->header(Connection => 'close');
    return RC_WAIT;
}

&main();

