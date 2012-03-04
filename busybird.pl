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

use BusyBird::Filter;

use BusyBird::Output;
use BusyBird::Timer;
use BusyBird::HTTPD;
use BusyBird::Worker::Twitter;
use BusyBird::Status;

require 'config.test.pl';

my $OPT_THRESHOLD_OFFSET = 0;
GetOptions(
    't=s' => \$OPT_THRESHOLD_OFFSET,
);

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
    ## ** 一つのInputが複数のTimerに紐付けられないように管理しないといけない
    ## &initiateTimer(BusyBird::Timer->new(interval => 120), [$input], [$output]);
    my $timer = BusyBird::Timer->new(interval => 120);
    $timer->addInput(BusyBird::Input::Twitter::PublicTimeline->new(name => 'public_tl', worker => $twitter_worker, no_timefile => 1),
                     BusyBird::Input::Twitter::HomeTimeline->new(name => 'home_tl', worker => $twitter_worker, no_timefile => 1));
    $timer->addOutput($output);
    
    ## &initiateTimer(BusyBird::Timer->new(interval => 2), [BusyBird::Input::Test->new(name => 'test_input', new_interval => 5, new_count => 3)],
    ##                [$output]);

    BusyBird::HTTPD->init($FindBin::Bin . "/resources/httpd");
    BusyBird::HTTPD->registerOutputs($output);
    BusyBird::HTTPD->start();
    POE::Kernel->run();
}

## sub initiateTimer {
##     my ($timer, $input_streams_ref, $filters_ref, $output_streams_ref) = @_;
##     POE::Session->create(
##         heap => {
##             input_streams => $input_streams_ref,
##             timer => $timer,
##             output_streams => $output_streams_ref,
##             new_statuses => [],
##             filters => $filters_ref,
##         },
##         inline_states => {
##             _start => sub {
##                 my ($kernel, $session) = @_[KERNEL, SESSION];
##                 $kernel->yield("timer_fire");
##                 ## $kernel->alias_set(sprintf("bb_main/%d", $session->ID));
##             },
##             
##             set_delay => sub {
##                 my $delay = $_[HEAP]->{timer}->getNextDelay();
##                 printf STDERR ("INFO: Following inputs will be checked in %.2f seconds.\n", $delay);
##                 foreach my $input (@{$_[HEAP]->{input_streams}}) {
##                     printf STDERR ("INFO:   %s\n", $input->getName());
##                 }
##                 $_[KERNEL]->delay('timer_fire', $delay);
##             },
##             
##             timer_fire   => sub {
##                 my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
##                 printf STDERR ("INFO: fire on input");
##                 foreach my $input (@{$heap->{input_streams}}) {
##                     printf STDERR (" %s", $input->getName());
##                 }
##                 print STDERR "\n";
## 
##                 @{$heap->{new_statuses}} = ();
##                 foreach my $input (@{$heap->{input_streams}}) {
##                     $input->getNewStatuses(undef, $session->ID, 'on_get_new_statuses');
##                 }
##             },
## 
##             on_get_new_statuses => sub {
##                 my ($kernel, $heap, $state, $session, $callstack, $ret_array) = @_[KERNEL, HEAP, STATE, SESSION, ARG0 .. ARG1];
##                 print STDERR ("main session(state => $state)\n");
##                 push(@{$heap->{new_statuses}}, $ret_array);
##                 if(int(@{$heap->{new_statuses}}) != int(@{$heap->{input_streams}})) {
##                     return;
##                 }
##                 printf STDERR ("main session: status input from %d streams.\n", int(@{$heap->{input_streams}}));
##                 
##                 my @new_statuses = ();
##                 foreach my $single_stream (@{$heap->{new_statuses}}) {
##                     push(@new_statuses, @$single_stream);
##                 }
##                 printf STDERR ("main session: %d statuses received.\n", int(@new_statuses));
##                 if (@new_statuses) {
##                     if(!@{$heap->{filters}}) {
##                         print STDERR ("ERROR: There is no filters in this session!!!\n");
##                         return $kernel->yield('on_filters_complete', undef, \@new_statuses);  ## for test
##                     }
##                     my $filter_index = 0;
##                     my $callstack = BusyBird::CallStack->newStack(undef, $session->ID, 'on_filters_complete',
##                                                                   filter_index => $filter_index);
##                     $heap->{filters}->[$filter_index]->execute($callstack, $session->ID, 'on_filter_execute', \@new_statuses);
##                 }else {
##                     return $kernel->yield('set_delay');
##                 }
##             },
##             on_filter_execute => sub {
##                 my ($kernel, $heap, $state, $session, $callstack, $statuses) = @_[KERNEL, HEAP, SESSION, STATE, ARG0, ARG1];
##                 print STDERR ("main session(state => $state)\n");
##                 my $filter_index = $callstack->get('filter_index');
##                 $filter_index++;
##                 if($filter_index < int(@{$heap->{filters}})) {
##                     $callstack->set('filter_index', $filter_index);
##                     $heap->{filters}->[$filter_index]->execute($callstack, $session->ID, 'on_filter_execute', $statuses);
##                 }else {
##                     $callstack->pop($statuses);
##                 }
##             },
##             on_filters_complete => sub {
##                 my ($kernel, $heap, $state, $session, $callstack, $statuses) = @_[KERNEL, HEAP, STATE, SESSION, ARG0, ARG1];
##                 print STDERR ("main session(state => $state)\n");
##                 ## for test: every status is given to every output.
##                 foreach my $output_stream (@{$heap->{output_streams}}) {
##                     $output_stream->pushStatuses($statuses);
##                     $output_stream->onCompletePushingStatuses();
##                 }
##                 return $kernel->yield('set_delay');
##             },
##             change_interval => sub {
##                 my ($kernel, $heap) = @_[KERNEL, HEAP];
##                 my $new_interval = ($_[ARG0] < $TIMER_INTERVAL_MIN ? $TIMER_INTERVAL_MIN : $_[ARG0]);
##                 $heap->{timer}->setInterval($new_interval);
##                 return $kernel->yield('set_delay');
##             },
##         },
##     );
## }


&main();

