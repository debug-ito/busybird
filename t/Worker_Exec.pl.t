#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More tests => 10;

BEGIN {
    sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }
    
    use_ok('POE');
    use_ok('BusyBird::Worker');
    use_ok('BusyBird::Worker::Exec');
    use_ok('FindBin');
}

chdir($FindBin::Bin);

my $worker = BusyBird::Worker::Exec->new();
isa_ok($worker, 'BusyBird::Worker');
isa_ok($worker, 'BusyBird::Worker::Exec');

my $SESSION_ALIAS = 'SESSION_ALIAS';
POE::Session->create(
    inline_states => {
        _start => sub {
            my ($kernel, $heap) = @_[KERNEL, HEAP];
            $kernel->alias_set($SESSION_ALIAS);
            $worker->startJob($SESSION_ALIAS, 'on_pwd', 'pwd');
            $worker->startJob($SESSION_ALIAS, 'on_sleep_echo', 'sleep 5; echo hogehogehoge');
            $worker->startJob($SESSION_ALIAS, 'on_false', 'sleep 3; false');
            $worker->startJob($SESSION_ALIAS, 'on_sort', join("\n", qw(sort strawberry apple orange melon)));
            $worker->startJob($SESSION_ALIAS, 'on_no_command', 'this_command_probably_does_not_exist');
            $worker->startJob($SESSION_ALIAS, 'on_ls_wild_card', 'ls *');
            $worker->startJob($SESSION_ALIAS, 'on_no_command_wild_card', 'this_does_not_exist_either *');
            $heap->{report_max} = 7;
            $heap->{report_count} = 0;
        },
        on_pwd => sub {
            my ($kernel, $state, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
            diag("--- $state");
            cmp_ok(int(@$output_objs), '==', 1, "output num: 1");
            is($input_obj, "pwd", "input: pwd");
            cmp_ok($exit_status, '==', 0, 'exit status: ok');

            my $data = $output_objs->[0];
            like($data, qr(/t$), "pwd's output ends with /t");
            
            $kernel->yield('check_end');
        },
        on_sleep_echo => sub {
            my ($kernel, $state, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
            diag("--- $state");
            cmp_ok(int(@$output_objs), "==", 1, 'output num: 1');
            is($input_obj, 'sleep 5; echo hogehogehoge', 'input OK');
            cmp_ok($exit_status, '==', 0, 'exit status ok');

            my $data = $output_objs->[0];
            is($data, "hogehogehoge\n", "output data OK");

            $kernel->yield('check_end');
        },
        on_false => sub {
            my ($kernel, $state, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
            diag("--- $state");
            cmp_ok(int(@$output_objs), "==", 1, 'output num: 1');
            is($input_obj, "sleep 3; false", "input OK");
            cmp_ok($exit_status, '==', 1, "exit status of false is 1");
            
            is($output_objs->[0], "", "no output data");

            $kernel->yield('check_end');
        },
        on_sort => sub {
            my ($kernel, $state, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
            diag("--- $state");
            cmp_ok(int(@$output_objs), "==", 1, 'output num: 1');
            is($input_obj, "sort\n" . "strawberry\n" . "apple\n" . "orange\n" . "melon", "input OK");
            cmp_ok($exit_status, '==', 0, "exit status OK");

            my $data = $output_objs->[0];
            is($data, join("\n", qw(apple melon orange strawberry)), 'data sorted');

            $kernel->yield('check_end');
        },
        on_no_command => sub {
            my ($kernel, $state, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
            diag("--- $state");
            cmp_ok(int(@$output_objs), "==", 1, 'output num: 1');
            is($input_obj, "this_command_probebly_does_not_exist");
            cmp_ok($exit_status, '!=', 0, "exit status OK");

            like($output_objs->[0], qr(command not found)i, "command not found");

            $kernel->yield('check_end');
        },
        on_ls_wild_card => sub {
            my ($kernel, $state, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
            fail($state);
            $kernel->yield('check_end');
        },
        on_no_command_wild_card => sub {
            my ($kernel, $state, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
            fail($state);
            $kernel->yield('check_end');
        },
        check_end => sub {
            my ($kernel, $heap) = @_[KERNEL, HEAP];
            $heap->{report_count}++;
            if($heap->{report_max} == $heap->{report_count}) {
                $kernel->alias_remove($SESSION_ALIAS);
            }
        },
    },
);

POE::Kernel->run();

pass('test ends here');
