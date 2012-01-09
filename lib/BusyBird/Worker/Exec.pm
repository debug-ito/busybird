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

