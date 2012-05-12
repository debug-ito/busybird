#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
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
    note('------ direct method calls');
    is(ref($test), 'BusyBird::Test::Object', 'object type ok');
    is($test->getString(), 'initial_text', "getString OK");
    &checkDisassembled('initial_text', $test->disassemble());
}

my $sync_cv = AnyEvent->condvar;

$sync_cv->begin();
$worker_obj->startJob(
    method => 'getString',
    cb => sub {
        my ($status, @data) = @_;
        note('------- getString');
        cmp_ok($status, '==', BusyBird::Worker::Object::STATUS_OK, 'method status: ok');
        cmp_ok(int(@data), "==", 1, 'one returning data.');
        
        is($data[0], "initial_text", "return value from the method is ok.");
        $sync_cv->end();
    });

$sync_cv->begin();
$worker_obj->startJob(
    method => 'getContext', context => 'scalar',
    cb => sub {
        my ($status, @data) = @_;
        note('------- getContext in scalar');
        cmp_ok($status, '==', BusyBird::Worker::Object::STATUS_OK, 'method status: ok');
        is($data[0], 'scalar', "data: scalar");
        $sync_cv->end();
    });

$sync_cv->begin();
$worker_obj->startJob(
    method => 'getContext', context => 'list',
    cb => sub {
        my ($status, @data) = @_;
        note('------- getContext in list');

        cmp_ok($status, '==', BusyBird::Worker::Object::STATUS_OK, 'method status: OK');
        is($data[0], 'list', 'returned data: list');
        $sync_cv->end();
    });

$sync_cv->begin();
$worker_obj->startJob(
    method => 'disassemble',
    cb => sub {
        my ($status, @data) = @_;
        note('-------- diassemble');
        cmp_ok($status, '==', BusyBird::Worker::Object::STATUS_OK, 'method status: ok');
        &checkDisassembled('initial_text', @data);
        $sync_cv->end();
    }
);

$sync_cv->recv();

$sync_cv = AnyEvent->condvar;
$worker_obj->getTargetObject()->setString('//');

$sync_cv->begin();
$worker_obj->startJob(
    method => 'cat', args => [qw(foo bar buzz)], context => 's',
    cb => sub {
        my ($status, @data) = @_;
        note('------- cat');
        cmp_ok($status, '==', BusyBird::Worker::Object::STATUS_OK, 'method status: ok');
        is($data[0], 'foo//bar//buzz', 'returnd data: ok');
        $sync_cv->end();
    }
);

$sync_cv->begin();
$worker_obj->startJob(
    method => 'not_exist', args => [1],
    cb => sub {
        my ($status, @data) = @_;
        note('------- not_exist');
        cmp_ok($status, '==', BusyBird::Worker::Object::STATUS_NO_METHOD, 'method status: no method');
        like($data[0], qr|not_exist.*undefined.*BusyBird::Test::Object|, 'error message');
        $sync_cv->end();
    }
);

$sync_cv->begin();
$worker_obj->startJob(
    method => 'do_not_call_me', context => 's',
    cb => sub {
        my ($status, @data) = @_;
        note('------- do_not_call_me');
        cmp_ok($status, '==', BusyBird::Worker::Object::STATUS_METHOD_DIES, "method dies");
        is($data[0], "I said do not call me!!!\n", "exception object is in data.");
        $sync_cv->end();
    }
);

$sync_cv->recv();
done_testing();

