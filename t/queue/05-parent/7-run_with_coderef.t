use strict;
use warnings;

use Test::More;
use Test::Exception;

BEGIN {
    use_ok('BusyBird::Defer::Queue');
}

my @ret = ();

sub pusher {
    my $val = shift;
    return sub {
        my ($d, $param) = @_;
        push(@ret, $val);
        $param ||= 0;
        $d->done($param + $val);
    };
}

my $defer = new_ok('BusyBird::Defer::Queue');
lives_ok { $defer->do(pusher(1), pusher(2), pusher(3)) } 'do() pushers.';
lives_ok {
    $defer->run(sub { my $sum = shift; push(@ret, $sum) });
} 'run() accepts a coderef';

is_deeply(\@ret, [1, 2, 3, 6], 'ret OK');

done_testing();






