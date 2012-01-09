#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 10;

BEGIN {
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
    return map {pack("C"), $_} (unpack("C*", $self->{string}));
}

sub cat {
    my ($self, @strings) = @_;
    sleep(10);
    return join($self->{string}, @strings);
}

package main;

my $worker_obj = BusyBird::Worker::Object->new(
    BusyBird::Test::Object->new("initial_text"),
);


my $WORKER_OBJECT_SESSION = "main_session_alias";
POE::Session->create(
    inline_states => {
        _start => sub {
            my ($kernel) = $_[KERNEL];
            $kernel->alias_set($WORKER_OBJECT_SESSION);
            $worker_obj->startJob($WORKER_OBJECT_SESSION, 'report1', {method => 'getString'});
            return 0;
        },
        report1 => sub {
            my ($kernel, $output_objs, $input_obj, $exit_status) = @_[KERNEL, ARG0, ARG1, ARG2];
            diag('------- report1');
            is(ref($output_objs), 'ARRAY', 'Returning output_objs is array,');
            cmp_ok(int(@$output_objs), "==", 1, 'and it has one element.');
            
            my $output_obj = $output_objs->[0];
            my ($status, $data) = ($output_obj->{status}, $output_obj->{data});
            
            cmp_ok($status, '==', 0, 'Exit status ok');
            is(ref($data), 'ARRAY', 'Returning data is an array (list context by default)');
            cmp_ok(int(@$data), "==", 1, 'one returning data.');
            is($data->[0], "initial_text", "return value from the method is ok.");

            $kernel->yield('final');
        },
        final => sub {
            $_[KERNEL]->alias_remove($WORKER_OBJECT_SESSION);
            pass('the test successfully ends here');
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
    }
);

POE::Kernel->run();
