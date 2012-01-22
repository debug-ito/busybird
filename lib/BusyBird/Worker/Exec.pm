package BusyBird::Worker::Exec;
use base ('BusyBird::Worker');

use strict;
use warnings;
use BusyBird::Worker;

sub new {
    my ($class) = @_;
    return $class->SUPER::new(
        Program => sub {
            POE::Kernel->stop();
            my $input_str = "";
            my $input_char = undef;
            while(1) {
                if(!sysread(STDIN, $input_char, 1)) {
                    last;
                }
                last if $input_char eq "\n";
                $input_str .= $input_char;
            }
            exec($input_str);
        },
        StdoutFilter => POE::Filter::Stream->new(),
    );
}

1;

