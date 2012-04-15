#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('BusyBird::Worker::Exec');
    use_ok('FindBin');
}

chdir($FindBin::Bin);

my $worker = 'BusyBird::Worker::Exec';
my $sync_cv = AnyEvent->condvar;

$sync_cv->begin();
$worker->startJob(
    command => 'pwd',
    cb => sub {
        my ($exit_status, $stdout, $stderr) = @_;
        diag("--- pwd");
        cmp_ok($exit_status, '==', 0, 'exit status: ok');

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
        cmp_ok($exit_status, '==', 0, 'exit status ok');

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
        cmp_ok($exit_status >> 8, '==', 1, "exit status of false is 1");
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
        cmp_ok($exit_status, '==', 0, "exit status OK");

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
        cmp_ok($exit_status >> 8, '==', 126, "exit value: 126");
        $sync_cv->end();
    }
);

$sync_cv->begin();
$worker->startJob(
    command => 'ls *',
    cb => sub {
        my ($exit_status, $stdout, $stderr) = @_;
        diag("--- ls wild card");
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
        cmp_ok($exit_status >> 8, "==", 127, "exit value: 127");
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
