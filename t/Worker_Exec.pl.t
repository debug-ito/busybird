#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;

BEGIN {
    ## sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }
    ## sub POE::Kernel::ASSERT_DEFAULT   () { 1 }
    
    ## use_ok('POE');
    ## use_ok('BusyBird::CallStack');
    ## use_ok('BusyBird::Worker');
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('AnyEvent::Util');
    use_ok('BusyBird::Worker::Exec');
    use_ok('FindBin');
}

chdir($FindBin::Bin);

## my $worker = BusyBird::Worker::Exec->new();
## isa_ok($worker, 'BusyBird::Worker');
## isa_ok($worker, 'BusyBird::Worker::Exec');

my $worker = 'BusyBird::Worker::Exec';
my $sync_cv = AnyEvent->condvar;

$sync_cv->begin();
$worker->startJob(
    command => 'pwd',
    cb => sub {
        my ($exit_status, $stdout, $stderr) = @_;
        diag("--- pwd");
        ## isa_ok($callstack, 'BusyBird::CallStack');
        ## cmp_ok($callstack->size, '==', 0);
        ## cmp_ok(int(@$output_objs), '==', 1, "output num: 1");
        ## is($input_obj, "pwd", "input: pwd");
        cmp_ok($exit_status, '==', 0, 'exit status: ok');

        ## my $data = $output_objs->[0];
        like($stdout, qr(/t$), "pwd's output ends with /t");
        is($stderr, '');
        $sync_cv->end();
    },
);

$sync_cv->begin();
$worker->startJob(
    command => 'sleep 5; echo hogehogehoge',
    cb => sub {
        my ($exit_status, $stdout, $stderr) = @_;
        diag("--- sleep; echo");
        ## isa_ok($callstack, 'BusyBird::CallStack');
        ## cmp_ok($callstack->size, '==', 0);
        ## cmp_ok(int(@$output_objs), "==", 1, 'output num: 1');
        ## is($input_obj, 'sleep 5; echo hogehogehoge', 'input OK');
        cmp_ok($exit_status, '==', 0, 'exit status ok');

        ## my $data = $output_objs->[0];
        is($stdout, "hogehogehoge\n", "output data OK");
        is($stderr, "");
        $sync_cv->end();
    },
);

$sync_cv->begin();
$worker->startJob(
    command => 'sleep 3; false',
    cb => sub {
        my ($exit_status, $stdout, $stderr) = @_;
        diag("--- sleep; false");
        ## isa_ok($callstack, 'BusyBird::CallStack');
        ## cmp_ok($callstack->size, '==', 0);
        ## cmp_ok(int(@$output_objs), "==", 0, 'output num: 0');
        ## is($input_obj, "sleep 3; false", "input OK");
        cmp_ok($exit_status >> 8, '==', 1, "exit status of false is 1");
        ## my $data = join('', @$output_objs);
        is($stdout, '', 'no output');
        is($stderr, '');
        $sync_cv->end();
    },
);

$sync_cv->begin();
$worker->startJob(
    command => [qw(echo arguments in an arrayref)],
    cb => sub {
        my ($exit_status, $stdout, $stderr) = @_;
        diag('--- echo (arguments in an arrayref)');
        cmp_ok($exit_status, '==', 0);
        is($stdout, "arguments in an arrayref\n");
        is($stderr, "");
        $sync_cv->end();
    }
);

$sync_cv->begin();
$worker->startJob(
    command => 'echo hogege >&2',
    cb => sub {
        my ($exit_status, $stdout, $stderr) = @_;
        diag('--- echo (redirected to stderr)');
        cmp_ok($exit_status, '==', 0);
        is($stdout, '');
        is($stderr, "hogege\n");
        $sync_cv->end();
    }
);

$sync_cv->begin();
$worker->startJob(
    command => 'sort',
    input_data => join("\n", qw(strawberry apple orange melon)),
    cb => sub {
        my ($exit_status, $stdout, $stderr) = @_;
        diag("--- sort");
        ## isa_ok($callstack, 'BusyBird::CallStack');
        ## cmp_ok($callstack->size, '==', 0);
        ## cmp_ok(int(@$output_objs), "==", 1, 'output num: 1');
        ## is($input_obj, "sort\n" . "strawberry\n" . "apple\n" . "orange\n" . "melon", "input OK");
        cmp_ok($exit_status, '==', 0, "exit status OK");

        ## my $data = $output_objs->[0];
        is($stdout, join("\n", qw(apple melon orange strawberry)) . "\n", 'data sorted');
        is($stderr, '');
        $sync_cv->end();
    }
);

$sync_cv->begin();
$worker->startJob(
    command => 'this_command_probably_does_not_exist',
    cb => sub {
        my ($exit_status, $stdout, $stderr) = @_;
        diag("--- no command (single)");
        ## isa_ok($callstack, 'BusyBird::CallStack');
        ## cmp_ok($callstack->size, '==', 0);
        ## cmp_ok(int(@$output_objs), "==", 1, 'output num: 1');
        ## is($input_obj, "this_command_probably_does_not_exist");
        cmp_ok($exit_status >> 8, '==', 126, "exit value: 126");
        ## is($stdout, '');
        ## is($stderr, '');
        $sync_cv->end();
    }
);

$sync_cv->begin();
$worker->startJob(
    command => 'ls *',
    cb => sub {
        my ($exit_status, $stdout, $stderr) = @_;
        diag("--- ls wild card");
        ## isa_ok($callstack, 'BusyBird::CallStack');
        ## cmp_ok($callstack->size, '==', 0);
        ## cmp_ok(int(@$output_objs), "==", 1, "output num: 1");
        ## is($input_obj, "ls *");
        cmp_ok($exit_status, "==", 0, "exit status: ok");

        my @files = split(/\s+/, $stdout);
        cmp_ok(int(@files), ">", "1", "multiple files in this directory");
        diag("File: $_") foreach @files;
        $sync_cv->end();
    }
);

$sync_cv->begin();
$worker->startJob(
    command => 'this_does_not_exist_either *',
    cb => sub {
        my ($exit_status, $stdout, $stderr) = @_;
        diag("--- no command (wild card)");
        ## isa_ok($callstack, 'BusyBird::CallStack');
        ## cmp_ok($callstack->size, '==', 0);
        ## cmp_ok(int(@$output_objs), "==", 0, 'output num: 0');
        ## is($input_obj, 'this_does_not_exist_either *', "input_obj: ok");
        cmp_ok($exit_status >> 8, "==", 127, "exit value: 127");
        ## is($stdout, '');
        ## is($stderr, '');
        $sync_cv->end();
    }
);

$sync_cv->begin();
$worker->startJob(
    command => 'true',
    cb => sub {
        my ($exit_status) = @_;
        cmp_ok($exit_status, '==', 0);
        $sync_cv->end();
    }
);


$sync_cv->recv();
done_testing();

## POE::Session->create(
##     inline_states => {
##         _start => sub {
##             my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
##             $worker->startJob(undef, $session->ID, 'on_pwd', 'pwd');
##             $worker->startJob(undef, $session->ID, 'on_sleep_echo', 'sleep 5; echo hogehogehoge');
##             $worker->startJob(undef, $session->ID, 'on_false', 'sleep 3; false');
##             $worker->startJob(undef, $session->ID, 'on_sort', join("\n", qw(sort strawberry apple orange melon)));
##             $worker->startJob(undef, $session->ID, 'on_no_command', 'this_command_probably_does_not_exist');
##             $worker->startJob(undef, $session->ID, 'on_ls_wild_card', 'ls *');
##             $worker->startJob(undef, $session->ID, 'on_no_command_wild_card', 'this_does_not_exist_either *');
##             $heap->{report_max} = 7;
##             $heap->{report_count} = 0;
##         },
##         _stop => sub {},
##         on_pwd => sub {
##             my ($kernel, $state, $callstack, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
##             diag("--- $state");
##             isa_ok($callstack, 'BusyBird::CallStack');
##             cmp_ok($callstack->size, '==', 0);
##             cmp_ok(int(@$output_objs), '==', 1, "output num: 1");
##             is($input_obj, "pwd", "input: pwd");
##             cmp_ok($exit_status, '==', 0, 'exit status: ok');
## 
##             my $data = $output_objs->[0];
##             like($data, qr(/t$), "pwd's output ends with /t");
##             diag(sprintf('output data: %s', $data));
##             
##             $kernel->yield('check_end');
##         },
##         on_sleep_echo => sub {
##             my ($kernel, $state, $callstack, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
##             diag("--- $state");
##             isa_ok($callstack, 'BusyBird::CallStack');
##             cmp_ok($callstack->size, '==', 0);
##             cmp_ok(int(@$output_objs), "==", 1, 'output num: 1');
##             is($input_obj, 'sleep 5; echo hogehogehoge', 'input OK');
##             cmp_ok($exit_status, '==', 0, 'exit status ok');
## 
##             my $data = $output_objs->[0];
##             is($data, "hogehogehoge\n", "output data OK");
## 
##             $kernel->yield('check_end');
##         },
##         on_false => sub {
##             my ($kernel, $state, $callstack, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
##             diag("--- $state");
##             isa_ok($callstack, 'BusyBird::CallStack');
##             cmp_ok($callstack->size, '==', 0);
##             cmp_ok(int(@$output_objs), "==", 0, 'output num: 0');
##             is($input_obj, "sleep 3; false", "input OK");
##             cmp_ok($exit_status >> 8, '==', 1, "exit status of false is 1");
##             my $data = join('', @$output_objs);
##             is($data, '', 'no output');
## 
##             $kernel->yield('check_end');
##         },
##         on_sort => sub {
##             my ($kernel, $state, $callstack, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
##             diag("--- $state");
##             isa_ok($callstack, 'BusyBird::CallStack');
##             cmp_ok($callstack->size, '==', 0);
##             cmp_ok(int(@$output_objs), "==", 1, 'output num: 1');
##             is($input_obj, "sort\n" . "strawberry\n" . "apple\n" . "orange\n" . "melon", "input OK");
##             cmp_ok($exit_status, '==', 0, "exit status OK");
## 
##             my $data = $output_objs->[0];
##             is($data, join("\n", qw(apple melon orange strawberry)) . "\n", 'data sorted');
## 
##             $kernel->yield('check_end');
##         },
##         on_no_command => sub {
##             my ($kernel, $state, $callstack, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
##             diag("--- $state");
##             isa_ok($callstack, 'BusyBird::CallStack');
##             cmp_ok($callstack->size, '==', 0);
##             cmp_ok(int(@$output_objs), "==", 1, 'output num: 1');
##             is($input_obj, "this_command_probably_does_not_exist");
##             cmp_ok($exit_status >> 8, '==', 127, "exit value: 127");
## 
##             like($output_objs->[0], qr(command not found)i, "command not found");
## 
##             $kernel->yield('check_end');
##         },
##         on_ls_wild_card => sub {
##             my ($kernel, $state, $callstack, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
##             diag("--- $state");
##             isa_ok($callstack, 'BusyBird::CallStack');
##             cmp_ok($callstack->size, '==', 0);
##             cmp_ok(int(@$output_objs), "==", 1, "output num: 1");
##             is($input_obj, "ls *");
##             cmp_ok($exit_status, "==", 0, "exit status: ok");
## 
##             my $data = $output_objs->[0];
##             my @files = split(/\s+/, $data);
##             cmp_ok(int(@files), ">", "1", "multiple files in this directory");
##             diag("File: $_") foreach @files;
##             $kernel->yield('check_end');
##         },
##         on_no_command_wild_card => sub {
##             my ($kernel, $state, $callstack, $output_objs, $input_obj, $exit_status) = @_[KERNEL, STATE, ARG0 .. $#_];
##             diag("--- $state");
##             isa_ok($callstack, 'BusyBird::CallStack');
##             cmp_ok($callstack->size, '==', 0);
##             cmp_ok(int(@$output_objs), "==", 0, 'output num: 0');
##             is($input_obj, 'this_does_not_exist_either *', "input_obj: ok");
##             cmp_ok($exit_status >> 8, "==", 127, "exit value: 127");
##             $kernel->yield('check_end');
##         },
##         check_end => sub {
##             my ($kernel, $heap) = @_[KERNEL, HEAP];
##             $heap->{report_count}++;
##         },
##     },
## );
## 
## POE::Kernel->run();
## 
## pass('test ends here');
## done_testing();
