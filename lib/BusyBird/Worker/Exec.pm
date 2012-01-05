package BusyBird::Worker::Exec;

use strict;
use BusyBird::Worker;

sub create {
    my ($class) = @_;
    return BusyBird::Worker->new(
        Program => sub {
            POE::Kernel->stop();
            my $input_line;
            {
                $/ = undef;
                $input_line = <STDIN>;
            }
            chomp $input_line;
            exec($input_line);
        },
        StdoutFilter => POE::Filter::Line->new(),
    );
}

1;

