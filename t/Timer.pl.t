#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

BEGIN {
    sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }
    sub POE::Kernel::ASSERT_DEFAULT   () { 1 }
    use_ok('POE');
    use_ok('BusyBird::Timer');
    use_ok('BusyBird::Input::Test');
    use_ok('BusyBird::Input::Twitter::PublicTimeline');
}

POE::Session->create(
    heap => {
        timer => undef,
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
            $heap->{timer}->addInput(new_ok('BusyBird::Input::Test', [name => 'test1', new_interval => 1, new_count => 5]));
            $heap->{timer}->_getNewStatuses(undef, $session->ID, '_getNewStatuses_1input');
        },
        _getNewStatuses_1input => sub {
            my ($kernel, $heap, $session, $state, $callstack, $ret_array) = @_[KERNEL, HEAP, SESSION, STATE, ARG0 .. ARG1];
            diag($state);
            isa_ok($callstack, 'BusyBird::CallStack');
            cmp_ok($callstack->frameNum, '==', 0);
            is(ref($ret_array), 'ARRAY');
            cmp_ok(int(@$ret_array), '==', 5);
            $kernel->yield('finish');
        },
        finish => sub {
            done_testing();
        },
    },
);

POE::Kernel->run();




