#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 71;

BEGIN {
    sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }
    use_ok('POE');
    use_ok('BusyBird::Worker');
    use_ok('BusyBird::Worker::Object');
}

package BusyBird::Test::Object;

sub new {
    my ($class, $str) = @_;
    return bless {string => $str}, $class;
}

sub getString {
    sleep(3);
    return $_[0]->{string};
}

sub setString {
    my ($self, $string) = @_;
    $self->{string} = $string;
}

sub getContext {
    if(wantarray) {
        sleep(5);
        return "list";
    }else {
        sleep(8);
        return 'scalar';
    }
}

sub disassemble {
    my ($self) = @_;
    sleep(8);
    my @values = unpack('C*', $self->{string});
    return map {pack("C", $_)} @values;
}

sub cat {
    my ($self, @strings) = @_;
    sleep(10);
    return join($self->{string}, @strings);
}

sub do_not_call_me {
    my ($self) = @_;
    die("I said do not call me!!!\n");
}


#######################################################
package main;

sub checkDisassembled {
    my ($orig_text, @disassembled) = @_;
    cmp_ok(int(@disassembled), '==', length($orig_text), 'diassembled length: ok');
    for (my $i = 0 ; $i < int(@disassembled) ; $i++) {
        is($disassembled[$i], substr($orig_text, $i, 1), sprintf('diassembled %d: %s', $i, $disassembled[$i]));
    }
}

my $worker_obj = BusyBird::Worker::Object->new(
    BusyBird::Test::Object->new("initial_text"),
);

{
    my $test = $worker_obj->getTargetObject();
    diag('------ before POE::Session');
    is(ref($test), 'BusyBird::Test::Object', 'object type ok');
    is($test->getString(), 'initial_text', "getString OK");
    &checkDisassembled('initial_text', $test->disassemble());
}


my $WORKER_OBJECT_SESSION = "main_session_alias";
POE::Session->create(
    heap => {report_done => {}},
    inline_states => {
        _start => sub {
            my ($kernel) = $_[KERNEL];
            $kernel->alias_set($WORKER_OBJECT_SESSION);
            $worker_obj->startJob($WORKER_OBJECT_SESSION, 'report1', {method => 'getString'});
            $worker_obj->startJob($WORKER_OBJECT_SESSION, 'report2', {method => 'getContext', context => 'scalar'});
            $worker_obj->startJob($WORKER_OBJECT_SESSION, 'report3', {method => 'getContext', context => 'list'});
            $worker_obj->startJob($WORKER_OBJECT_SESSION, 'report4', {method => 'disassemble'});
            return 0;
        },
        report1 => sub {
            my ($kernel, $output_objs, $input_obj, $exit_status) = @_[KERNEL, ARG0, ARG1, ARG2];
            diag('------- report1');
            is(ref($output_objs), 'ARRAY', 'Returning output_objs is array,');
            cmp_ok(int(@$output_objs), "==", 1, 'and it has one element.');
            is($input_obj->{method}, 'getString', 'Input was getString method');
            cmp_ok($exit_status, '==', 0, 'exit status ok');
            
            my $output_obj = $output_objs->[0];
            my ($status, $data) = ($output_obj->{status}, $output_obj->{data});
            
            cmp_ok($status, '==', BusyBird::Worker::Object::STATUS_OK, 'method status: ok');
            is(ref($data), 'ARRAY', 'Returning data is an array (list context by default)');
            cmp_ok(int(@$data), "==", 1, 'one returning data.');
            
            is($data->[0], "initial_text", "return value from the method is ok.");

            $kernel->yield('check_end', 'report1');
        },
        report2 => sub {
            my ($kernel, $output_objs, $input_obj, $exit_status) = @_[KERNEL, ARG0, ARG1, ARG2];
            diag('------- report2');
            cmp_ok(int(@$output_objs), '==', 1, '1 output');
            cmp_ok($exit_status, '==', 0, 'exit status OK');
            is($input_obj->{method}, 'getContext', 'method: getContext');
            is($input_obj->{context}, 'scalar', 'context:scalar');

            my $output_obj = $output_objs->[0];

            cmp_ok($output_obj->{status}, '==', BusyBird::Worker::Object::STATUS_OK, 'method status: ok');
            is($output_obj->{data}, 'scalar', "data: scalar");

            $kernel->yield('check_end', 'report2');
        },
        report3 => sub {
            my ($kernel, $output_objs, $input_obj, $exit_status) = @_[KERNEL, ARG0, ARG1, ARG2];
            diag('------- report3');
            cmp_ok(int(@$output_objs), '==', 1, '1 output');
            cmp_ok($exit_status, '==', 0, 'exit status OK');
            is($input_obj->{context}, 'list', 'input context: list');

            my $output_obj = $output_objs->[0];

            cmp_ok($output_obj->{status}, '==', BusyBird::Worker::Object::STATUS_OK, 'method status: OK');
            is(ref($output_obj->{data}), 'ARRAY', 'data: is an array');

            my @returned_data = @{$output_obj->{data}};

            cmp_ok(int(@returned_data), '==', 1, 'number of returned data: 1');
            is($returned_data[0], 'list', 'returned data: list');

            $kernel->yield('check_end', 'report3');
        },
        report4 => sub {
            my ($kernel, $output_objs, $input_obj) = @_[KERNEL, ARG0, ARG1];
            diag('-------- report4');
            is($input_obj->{method}, 'disassemble', 'method: disassemble');

            my ($status, @data) = ($output_objs->[0]->{status}, @{$output_objs->[0]->{data}});

            cmp_ok($status, '==', BusyBird::Worker::Object::STATUS_OK, 'method status: ok');
            &checkDisassembled('initial_text', @data);

            $kernel->yield('check_end', 'report4');

            $worker_obj->getTargetObject()->setString('//');
            $worker_obj->startJob($WORKER_OBJECT_SESSION, 'report5', {method => 'cat', args => [qw(foo bar buzz)], context => 's'});
            $worker_obj->startJob($WORKER_OBJECT_SESSION, 'report6', {method => 'not_exist', args => [1]});
            $worker_obj->startJob($WORKER_OBJECT_SESSION, 'report7', {method => 'do_not_call_me', context => 's'});
        },
        report5 => sub {
            my ($kernel, $output_objs, $input_obj, $exit_status) = @_[KERNEL, ARG0, ARG1, ARG2];
            diag('------- report5');
            cmp_ok(int(@$output_objs), '==', 1, 'output num: 1');
            is($input_obj->{method}, 'cat', 'method: cat');
            is($input_obj->{context}, 's', 'context: s');
            cmp_ok(int(@{$input_obj->{args}}), '==', 3, 'args num: 3');

            my ($status, $data) = ($output_objs->[0]->{status}, $output_objs->[0]->{data});

            cmp_ok($status, '==', BusyBird::Worker::Object::STATUS_OK, 'method status: ok');
            is($data, 'foo//bar//buzz', 'returend data: ok');

            $kernel->yield('check_end', 'report5');
        },
        report6 => sub {
            my ($kernel, $output_objs, $input_obj, $exit_status) = @_[KERNEL, ARG0, ARG1, ARG2];
            diag('------- report6');
            cmp_ok(int(@$output_objs), '==', 1, 'output num: 1');
            cmp_ok($exit_status, '==', 0, 'exit status: ok');
            is($input_obj->{method}, 'not_exist', 'method: not_exist');

            my ($status, $data) = ($output_objs->[0]->{status}, $output_objs->[0]->{data});

            cmp_ok($status, '==', BusyBird::Worker::Object::STATUS_NO_METHOD, 'method status: no method');
            like($data, qr|not_exist.*undefined.*BusyBird::Test::Object|, 'error message');

            $kernel->yield('check_end', 'report6');
        },
        report7 => sub {
            my ($kernel, $output_objs, $input_obj, $exit_status) = @_[KERNEL, ARG0, ARG1, ARG2];
            diag('------- report7');
            cmp_ok(int(@$output_objs), '==', 1, 'output num: 1');
            cmp_ok($exit_status, '==', 0, 'exit status: OK');
            is($input_obj->{method}, "do_not_call_me", "method: do_not_call_me");

            my ($status, $data) = ($output_objs->[0]->{status}, $output_objs->[0]->{data});

            cmp_ok($status, '==', BusyBird::Worker::Object::STATUS_METHOD_DIES, "method dies");
            is($data, "I said do not call me!!!\n", "exception object is in data.");

            $kernel->yield('check_end', 'report7');
        },
        check_end => sub {
            my ($kernel, $heap, $end_token) = @_[KERNEL, HEAP, ARG0];
            my $report_done_list = $heap->{report_done};
            $report_done_list->{$end_token} = 1;
            my $is_end = 1;
            foreach my $token (qw(report1 report2 report3 report4 report5 report6 report7)) {
                $is_end = 0 if !$report_done_list->{$token};
            }
            if ($is_end) {
                $_[KERNEL]->alias_remove($WORKER_OBJECT_SESSION);
                pass('the test successfully ends here');
            }
        },
        
        ## timer_fire => sub {
        ##     my ($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];
        ##     print STDERR (">> workerTest fired.\n");
        ##     $worker->startJob($session->ID, 'on_report', $heap->{commands}->[$heap->{next_command_index}]);
        ##     $heap->{next_command_index} = ($heap->{next_command_index} + 1) % int(@{$heap->{commands}});
        ##     $kernel->delay('timer_fire', 30);
        ## },
        ## on_report => sub {
        ##     my ($reported_objs, $input_obj) = @_[ARG0, ARG1];
        ##     print  STDERR ">>>> REPORT Received <<<<\n";
        ##     ## print  STDERR "  Input: $input_obj\n";
        ##     printf STDERR ("  Output: num:%d\n  ", int(@$reported_objs));
        ##     for (my $i = 0 ; $i < @$reported_objs ; $i++) {
        ##         printf STDERR ("  Output index %d\n", $i);
        ##         print STDERR (Dumper($reported_objs->[$i]));
        ##     }
        ##     ## print  STDERR (join("\n  ", @$reported_objs));
        ##     ## print  STDERR "\n";
        ## }
    },
);

POE::Kernel->run();
