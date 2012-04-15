package BusyBird::Worker::Exec;
## use base ('BusyBird::Worker');

use strict;
use warnings;

use AnyEvent;
use AnyEvent::Util;

## use BusyBird::Worker;
## use POSIX qw(_exit);
## 
## sub new {
##     my ($class) = @_;
##     return $class->SUPER::new(
##         Program => sub {
##             ## POE::Kernel->stop();
##             my $input_str = "";
##             my $input_char = undef;
##             while(1) {
##                 if(!sysread(STDIN, $input_char, 1)) {
##                     last;
##                 }
##                 last if $input_char eq "\n";
##                 $input_str .= $input_char;
##             }
##             if(!exec($input_str)) {
##                 print "Command not found: $input_str\n";
##                 _exit(127);
##             }
##         },
##         StdoutFilter => POE::Filter::Stream->new(),
##     );
## }

sub startJob {
    my ($self_class, %params) = @_;
    my $stdout = '';
    my $stderr = '';
    if(!defined($params{command})) {
        die "No command param.";
    }
    my $stdin = undef;
    if(defined($params{input_data})) {
        $stdin = \$params{input_data};
    }
    if(!defined($params{cb})) {
        die "No cb param.";
    }
    my $cb = $params{cb};
    my %run_cmd_params = (
        '>'  => \$stdout,
        '2>' => \$stderr,
    );
    $run_cmd_params{'<'} = $stdin if defined($stdin);
    
    my $cv = run_cmd(
        $params{command},
        %run_cmd_params,
    );
    $cv->cb(
        sub {
            my $exit_status = $_[0]->recv;
            $cb->($exit_status, $stdout, $stderr);
        }
    );
}

1;

