#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

BEGIN {
    sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }
    sub POE::Kernel::ASSERT_DEFAULT   () { 1 }
    use_ok('POE');
    use_ok('BusyBird::Worker::Twitter');
    use_ok('BusyBird::Timer');
    use_ok('BusyBird::Input');
    use_ok('BusyBird::Input::Test');
    use_ok('BusyBird::Input::Twitter::PublicTimeline');
    use_ok('BusyBird::Filter');
    use_ok('BusyBird::Filter::Coderef');
}

my $test_finished = 0;

my %got_statuses_expects = (
    test1 => {cmp => '==', num => 3},
    test2 => {cmp => '==', num => 7},
    test3 => {cmp => '==', num => 13},
    public_tl => {cmp => '>=', num => 1},
);

sub createPublicTimelineInput {
    my $worker = new_ok('BusyBird::Worker::Twitter', [traits => [qw(API::REST API::Lists)]]);
    return new_ok('BusyBird::Input::Twitter::PublicTimeline', [
        name => 'public_tl',
        worker => $worker,
        no_timefile => 1,
    ]);
}

sub checkStatuses {
    my ($statuses, @expected_inputs) = @_;
    my %got_inputs = ();
    foreach my $status (@$statuses) {
        my $inputname = $status->getInputName;
        $got_inputs{$inputname}++;
    }
    foreach my $exp_input (@expected_inputs) {
        ok(defined($got_inputs{$exp_input}));
        cmp_ok($got_inputs{$exp_input},
               $got_statuses_expects{$exp_input}->{cmp},
               $got_statuses_expects{$exp_input}->{num},
               "input from $exp_input");
        delete $got_inputs{$exp_input};
    }
    cmp_ok(int(keys(%got_inputs)), '==', 0);
}

my @test_filter_sequence = ();

sub createFilter {
    my ($filter_seq_no, $delay_sec) = @_;
    return new_ok('BusyBird::Filter::Coderef',
                  [coderef => sub {
                       my ($callstack, $ret_session, $ret_event, $statuses) = @_;
                       $callstack = BusyBird::CallStack->newStack($callstack, $ret_session, $ret_event, statuses => $statuses);
                       POE::Session->create(
                           inline_states => {
                               _default => sub {},
                               _start => sub {
                                   diag("Filter $filter_seq_no started.");
                                   $_[KERNEL]->delay('fire', $delay_sec);
                               },
                               fire => sub {
                                   diag("Filter $filter_seq_no ended.");
                                   push(@test_filter_sequence, $filter_seq_no);
                                   $callstack->pop($callstack->get('statuses'));
                               },
                           }
                       );
                   }]
              );
}

POE::Session->create(
    heap => {
        timer => undef,
        triinputs_count => 0,
    },
    inline_states => {
        _child => sub {
            ;
        },
        _stop => sub {
            ;
        },
        _start => sub {
            my ($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];
            $heap->{timer} = new_ok('BusyBird::Timer', [interval => 10, start_delay => -1, aliased => 1]);
            $heap->{timer}->addInput(new_ok('BusyBird::Input::Test', [
                name => 'test1',new_interval => 1, no_timefile => 1,
                new_count => $got_statuses_expects{test1}->{num}]));
            $heap->{timer}->addFilter(&createFilter(0, 5), &createFilter(1, 4), &createFilter(2, 3), &createFilter(3, 2));
            $heap->{timer}->_getNewStatuses(undef, $session->ID, '_getNewStatuses_1input');
        },
        _getNewStatuses_1input => sub {
            my ($kernel, $heap, $session, $state, $callstack, $ret_array) = @_[KERNEL, HEAP, SESSION, STATE, ARG0 .. ARG1];
            diag($state);
            isa_ok($callstack, 'BusyBird::CallStack');
            cmp_ok($callstack->frameNum, '==', 0);
            is(ref($ret_array), 'ARRAY');
            cmp_ok(int(@$ret_array), '==', 3);

            $heap->{timer}->addInput(new_ok('BusyBird::Input::Test', [name => 'test2', new_interval => 2, no_timefile => 1,
                                                                      new_count => $got_statuses_expects{test2}->{num}]));
            $heap->{timer}->addInput(new_ok('BusyBird::Input::Test', [name => 'test3', new_interval => 3, no_timefile => 1,
                                                                      new_count => $got_statuses_expects{test3}->{num}]));
            $heap->{timer}->_getNewStatuses(undef, $session->ID, '_getNewStatuses_3inputs');
        },
        _getNewStatuses_3inputs => sub {
            my ($kernel, $heap, $session, $state, $callstack, $ret_array) = @_[KERNEL, HEAP, SESSION, STATE, ARG0 .. ARG1];
            $heap->{triinputs_count}++;
            diag(sprintf("%s - count %d", $state, $heap->{triinputs_count}));
            my @expected_inputs = ('test1');
            if($heap->{triinputs_count} % 2 == 0) {
                push(@expected_inputs, 'test2');
            }
            if($heap->{triinputs_count} % 3 == 0) {
                push(@expected_inputs, 'test3');
            }
            &checkStatuses($ret_array, @expected_inputs);
            
            if($heap->{triinputs_count} >= 12) {
                $heap->{timer}->addInput(&createPublicTimelineInput());
                $heap->{timer}->_getNewStatuses(undef, $session->ID, '_getNewStatuses_4inputs');
            }else {
                $heap->{timer}->_getNewStatuses(undef, $session->ID, '_getNewStatuses_3inputs');
            }
        },
        _getNewStatuses_4inputs => sub {
            my ($kernel, $heap, $session, $state, $callstack, $ret_array) = @_[KERNEL, HEAP, SESSION, STATE, ARG0 .. ARG1];
            diag($state);
            &checkStatuses($ret_array, qw(test1 public_tl));
            $heap->{timer}->_executeFilters(undef, $session->ID, '_executeFilters', $ret_array);
        },
        _executeFilters => sub {
            my ($kernel, $heap, $session, $state, $callstack, $statuses) = @_[KERNEL, HEAP, SESSION, STATE, ARG0 .. ARG1];
            diag($state);
            &checkStatuses($statuses, qw(test1 public_tl));
            cmp_ok(int(@test_filter_sequence), '==', 4);
            foreach my $index (0 .. $#test_filter_sequence) {
                cmp_ok($test_filter_sequence[$index], '==', $index, "check filters's cascading sequence");
            }
            $kernel->yield('finish');
        },
        finish => sub {
            $test_finished = 1;
        },
    },
);

POE::Kernel->run();
ok($test_finished, 'test session properly finished.');
done_testing();




