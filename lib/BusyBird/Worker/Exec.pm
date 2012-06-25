package BusyBird::Worker::Exec;

use strict;
use warnings;

use AnyEvent;
use AnyEvent::Util;
use Carp;

sub startJob {
    my ($self_class, %params) = @_;
    my $stdout = '';
    my $stderr = '';
    if(!defined($params{command})) {
        croak "No command param.";
    }
    my $stdin = undef;
    if(defined($params{input_data})) {
        $stdin = \$params{input_data};
    }
    if(!defined($params{cb})) {
        croak "No cb param.";
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

