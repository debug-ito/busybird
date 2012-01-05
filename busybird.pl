#!/usr/bin/perl -w

use strict;
use warnings;
use Getopt::Long;
use Scalar::Util qw(refaddr);
use Encode;
use FindBin;

use POE;

use Net::Twitter;
use BusyBird::Input;
use BusyBird::Input::Twitter::HomeTimeline;
use BusyBird::Input::Twitter::List;
use BusyBird::Input::Test;
use BusyBird::Output;
use BusyBird::Judge;
use BusyBird::Timer;
use BusyBird::HTTPD;
use BusyBird::Worker::Exec;

require 'config.test.pl';

my $OPT_THRESHOLD_OFFSET = 0;
GetOptions(
    't=s' => \$OPT_THRESHOLD_OFFSET,
);

my $TIMER_INTERVAL_MIN = 60;
my $DEFAULT_STREAM_NAME = 'default';

my %notify_responses = ();

sub main {
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
    ## ** 一つのInputが複数のTimerに紐付けられないように管理しないといけない
    ## &initiateTimer(BusyBird::Timer->new(120), [$input], [$output]);
    ## &initiateTimer(
    ##     BusyBird::Timer->new(200),
    ##     [BusyBird::Input::Twitter::HomeTimeline->new(name => 'home', nt => $nt)],
    ##     [$output],
    ##     );
    
    ## &initiateTimer(BusyBird::Timer->new(2), [BusyBird::Input::Test->new(name => 'test_input', new_interval => 5, new_count => 3)],
    ##                [$output]);
    &workerTest();

    BusyBird::HTTPD->init($FindBin::Bin . "/resources/httpd");
    BusyBird::HTTPD->registerOutputs($output);
    BusyBird::HTTPD->start();
    POE::Kernel->run();
}

sub initiateTimer {
    my ($timer, $input_streams_ref, $output_streams_ref) = @_;
    POE::Session->create(
        heap => {
            input_streams => $input_streams_ref,
            timer => $timer,
            output_streams => $output_streams_ref,
        },
        inline_states => {
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
                
                ## ** Notify outputs of the complete of pushing statuses
                foreach my $output (@{$heap->{output_streams}}) {
                    $output->onCompletePushingStatuses();
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

sub workerTest {
    my $worker = BusyBird::Worker::Exec->create();
    my @commands = (
        'sleep 15; ls', 'sleep 3; ls -al /', "sleep 6; cat /home/toshio/patents.txt"
    );
    POE::Session->create(
        heap => {worker => $worker, next_command_index => 0, commands => \@commands},
        inline_states => {
            _start => sub { $_[KERNEL]->yield('timer_fire'); },
            timer_fire => sub {
                my ($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];
                print STDERR (">> workerTest fired.\n");
                $worker->startJob($session->ID, 'on_report', $heap->{commands}->[$heap->{next_command_index}]);
                $heap->{next_command_index} = ($heap->{next_command_index} + 1) % int(@{$heap->{commands}});
                $kernel->delay('timer_fire', 2);
            },
            on_report => sub {
                my ($reported_objs, $input_obj) = @_[ARG0, ARG1];
                print  STDERR ">>>> REPORT Received <<<<\n";
                print  STDERR "  Input: $input_obj\n";
                printf STDERR ("  Output: num:%d\n  ", int(@$reported_objs));
                print  STDERR (join("\n  ", @$reported_objs));
                print  STDERR "\n";
            }
        }
    );
}

&main();

