#!/usr/bin/perl -w

use strict;
use warnings;

use Getopt::Long;
use Scalar::Util qw(refaddr);
use Encode;
use FindBin;

sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }
sub POE::Kernel::ASSERT_DEFAULT    () { 1 }
use POE;



use Data::Dumper;

use Net::Twitter;
use BusyBird::Input;
use BusyBird::Input::Twitter::HomeTimeline;
use BusyBird::Input::Twitter::List;
use BusyBird::Input::Twitter::PublicTimeline;
use BusyBird::Input::Test;
use BusyBird::Output;
use BusyBird::Judge;
use BusyBird::Timer;
use BusyBird::HTTPD;
use BusyBird::Worker::Twitter;
use BusyBird::Status;

require 'config.test.pl';

my $OPT_THRESHOLD_OFFSET = 0;
GetOptions(
    't=s' => \$OPT_THRESHOLD_OFFSET,
);

my $TIMER_INTERVAL_MIN = 60;
my $DEFAULT_STREAM_NAME = 'default';

my %notify_responses = ();
my %config_parameters = &tempGetConfig();

sub main {
    ## ** TODO: support more sophisticated format of threshold offset (other than just seconds).
    BusyBird::Input->setThresholdOffset(int($OPT_THRESHOLD_OFFSET));
    my $twitter_worker = BusyBird::Worker::Twitter->new(
        traits   => [qw/OAuth API::REST API::Lists/],
        consumer_key        => $config_parameters{consumer_key},
        consumer_secret     => $config_parameters{consumer_secret},
        access_token        => $config_parameters{token},
        access_token_secret => $config_parameters{token_secret},
        ssl => 1,
    );
    ## my $input  = BusyBird::Input::Twitter::List->new(name => 'list_test',
    ##                                                  worker => $twitter_worker,
    ##                                                  owner_name => $config_parameters{owner_name},
    ##                                                  list_slug_name => $config_parameters{list_slug_name});
    my $output = BusyBird::Output->new($DEFAULT_STREAM_NAME);
    $output->judge(BusyBird::Judge->new());
    ## ** 一つのInputが複数のTimerに紐付けられないように管理しないといけない
    ## &initiateTimer(BusyBird::Timer->new(120), [$input], [$output]);
    &initiateTimer(
        BusyBird::Timer->new(120),
        ## [BusyBird::Input::Twitter::HomeTimeline->new(name => 'home', worker => $twitter_worker)],
        [BusyBird::Input::Twitter::PublicTimeline->new(name => 'public_tl', worker => $twitter_worker)],
        [$output],
        );
    
    ## &initiateTimer(BusyBird::Timer->new(2), [BusyBird::Input::Test->new(name => 'test_input', new_interval => 5, new_count => 3)],
    ##                [$output]);

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
            new_statuses => [],
        },
        inline_states => {
            _start => sub {
                my ($kernel, $session) = @_[KERNEL, SESSION];
                $kernel->yield("timer_fire");
                ## $kernel->alias_set(sprintf("bb_main/%d", $session->ID));
            },
            
            set_delay => sub {
                my $delay = $_[HEAP]->{timer}->getNextDelay();
                printf STDERR ("INFO: Following inputs will be checked in %.2f seconds.\n", $delay);
                foreach my $input (@{$_[HEAP]->{input_streams}}) {
                    printf STDERR ("INFO:   %s\n", $input->getName());
                }
                $_[KERNEL]->delay('timer_fire', $delay);
            },
            
            timer_fire   => sub {
                my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
                printf STDERR ("INFO: fire on input");
                foreach my $input (@{$heap->{input_streams}}) {
                    printf STDERR (" %s", $input->getName());
                }
                print STDERR "\n";

                @{$heap->{new_statuses}} = ();
                foreach my $input (@{$heap->{input_streams}}) {
                    $input->getNewStatuses(undef, $session->ID, 'on_get_new_statuses');
                }
            },

            on_get_new_statuses => sub {
                my ($kernel, $heap, $state, $callstack, $ret_array) = @_[KERNEL, HEAP, STATE, ARG0 .. ARG1];
                print STDERR ("main session(state => $state)\n");
                push(@{$heap->{new_statuses}}, $ret_array);
                if(int(@{$heap->{new_statuses}}) != int(@{$heap->{input_streams}})) {
                    return;
                }
                printf STDERR ("main session: status input from %d streams.\n", int(@{$heap->{input_streams}}));
                
                my @new_statuses = ();
                foreach my $single_stream (@{$heap->{new_statuses}}) {
                    push(@new_statuses, @$single_stream);
                }
                printf STDERR ("main session: %d statuses received.\n", int(@new_statuses));
                if (@new_statuses) {
                    foreach my $output_stream (@{$heap->{output_streams}}) {
                        $output_stream->pushStatuses(\@new_statuses);
                        $output_stream->onCompletePushingStatuses();
                    }
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


&main();

