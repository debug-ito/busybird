#!/usr/bin/perl -w
use strict;
use warnings;
use Getopt::Long;
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

my $OPT_THRESHOLD_OFFSET = 0;
GetOptions(
    't=s' => \$OPT_THRESHOLD_OFFSET,
    );

my $TIMER_INTERVAL_MIN = 60;
my $DEFAULT_STREAM_NAME = 'default';

my %notify_responses = ();
my $client_agent = BusyBird::ClientAgent->new();

sub main() {
    ## ** TODO: support more sophisticated format of threshold offset (other than just seconds).
    BusyBird::Input->setThresholdOffset(int($OPT_THRESHOLD_OFFSET));
    
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
    ## ** 一つのInputが複数のTimerに紐付けられないように管理しないといけない
    &initiateTimer(BusyBird::Timer->new(120), [$input], [$output]);
    &initiateTimer(
        BusyBird::Timer->new(200),
        [BusyBird::Input::Twitter::HomeTimeline->new(name => 'home', nt => $nt)],
        [$output],
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

sub initiateTimer() {
    my ($timer, $input_streams_ref, $output_streams_ref) = @_;
    POE::Session->create(
        heap => {
            input_streams => $input_streams_ref,
            timer => $timer,
            output_streams => $output_streams_ref,
        },
        inline_states => {
            ## タイムライン名でaliasを設定するといいのかもしれない。
            _start => sub { $_[KERNEL]->yield("timer_fire") },
            set_delay => sub {
                my $delay = $_[HEAP]->{timer}->getNextDelay();
                printf STDERR ("INFO: Following inputs will be checked in %.2f seconds.\n", $delay);
                foreach my $input (@{$_[HEAP]->{input_streams}}) {
                    printf STDERR ("INFO:   %s\n", $input->getName());
                }
                $_[KERNEL]->delay('timer_fire', $delay);
            },
            timer_fire   => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                printf STDERR ("INFO: fire on input");
                foreach my $input (@{$heap->{input_streams}}) {
                    printf STDERR (" %s", $input->getName());
                }
                print STDERR "\n";
                
                foreach my $input (@{$heap->{input_streams}}) {
                    my $statuses;
                    eval {
                        $statuses = $input->getNewStatuses();
                    };
                    if($@) {
                        printf STDERR ("ERROR: while getting input %s: %s\n", $input->getName(), $@);
                        next;
                    }
                    foreach my $output_stream (@{$heap->{output_streams}}) {
                        $output_stream->pushStatuses($statuses);
                    }
                }
                foreach my $output_stream (@{$heap->{output_streams}}) {
                    $output_stream->flushStatuses(); ## ** For test..
                }
                
                return $kernel->yield('set_delay');
            },
            change_interval => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                my $new_interval = ($_[ARG0] < $TIMER_INTERVAL_MIN ? $TIMER_INTERVAL_MIN : $_[ARG0]);
                $heap->{timer}->setInterval($new_interval);
                return $kernel->yield('set_delay');
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

