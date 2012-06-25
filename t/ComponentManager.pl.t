
use strict;
use warnings;

use Test::More;
use Test::SharedFork;

BEGIN {
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('BusyBird::Output');
    use_ok('BusyBird::Input');
    use_ok('BusyBird::ComponentManager');
}

my @output_names = qw(foo bar);
my @input_names = qw(hoge fuga);

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
    new_ok('BusyBird::Input', [name => $_, driver => 'BusyBird::InputDriver::Test']) foreach @input_names;
    BusyBird::ComponentManager->initComponents();
    AnyEvent->condvar->recv();
    done_testing();
}

sub checkFileAndRemove {
    my ($filename) = @_;
    ok(-r $filename, "File $filename exists") or return;
    unlink($filename);
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
    my @exp_input_files = map {"bbinput_${_}.time"} @input_names;
    &checkFileAndRemove($_) foreach (@exp_output_files, @exp_input_files);
    done_testing();
}

&main();
