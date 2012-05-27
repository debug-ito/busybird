
use strict;
use warnings;

use Test::More;
use Test::SharedFork;

BEGIN {
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('BusyBird::Output');
    use_ok('BusyBird::ComponentManager');
}

my @output_names = qw(foo bar);

sub main {
    my $pid = fork();
    ok(defined($pid), "fork successful") or die;
    if($pid) {
        &parent($pid);
    }else {
        &child()
    }
}

sub child {
    BusyBird::ComponentManager->init();
    new_ok('BusyBird::Output', [name => $_]) foreach @output_names;
    BusyBird::ComponentManager->initComponents();
    AnyEvent->condvar->recv();
    done_testing();
}

sub parent {
    my $child_pid = shift;
    my $wait = 3;
    note("Sleep $wait sec for the child to be initialized.");
    sleep $wait;
    kill "TERM", $child_pid;
    is(waitpid($child_pid, 0), $child_pid, "Child process $child_pid terminated");
    cmp_ok($? >> 8, "==", 0, "... and its return status is 0.");

    my @exp_output_files = map { "bboutput_${_}_statuses.json" } @output_names;
    foreach my $exp_output_file (@exp_output_files) {
        ok(-r $exp_output_file, "Output status file $exp_output_file exists.") or next;
        unlink($exp_output_file);
    }
    done_testing();
}

&main();
