package BusyBird::Worker::Exec;

use strict;
use BusyBird::Worker;

sub create {
    my ($class) = @_;
    return BusyBird::Worker->new(
        Program => sub {
            POE::Kernel->stop();
            my $input_str;
            {
                local $/ = undef;
                $input_str = <STDIN>;
            }
            chomp $input_str;
            exec($input_str);
        },
        StdoutFilter => POE::Filter::Line->new(),
    );
}

1;

