
use strict;
use warnings;

use Test::More;
use Test::Builder;

BEGIN {
    use_ok('BusyBird::Util', 'expandParam');
}

our $SCALAR_CONTEXT = 0;

sub testExpand {
    my ($in, $names, @exp) = @_;
    local $Test::Builder::Level += 1;
    my @got;
    if($SCALAR_CONTEXT) {
        $got[0] = expandParam($in, @$names);
    }else {
        @got = expandParam($in, @$names);
    }
    cmp_ok(int(@got), "==", int(@exp), "got size");
    foreach my $i (0 .. $#got) {
        is($got[$i], $exp[$i], "index $i");
    }
}

$SCALAR_CONTEXT = 0;
testExpand 10, ['num'], 10;
testExpand 'hoge', ['str'], 'hoge';
testExpand [qw(foo bar buzz)], [qw(a b c)], qw(foo bar buzz);
testExpand undef, ['undef'], undef;
testExpand {a => 'foo', b => 30, c => 'buzz'}, [qw(a b c)], 'foo', 30, 'buzz';
testExpand {a => 45, b => 12}, [qw(x y z a d)], undef, undef, undef, 45, undef;

$SCALAR_CONTEXT = 1;
testExpand 10, ['num'], 10;
testExpand 'hoge', ['str'], 'hoge';
testExpand [qw(foo bar buzz)], [qw(a b c)], qw(foo);
testExpand undef, ['undef'], undef;
testExpand {a => 'foo', b => 30, c => 'buzz'}, [qw(a b c)], 'foo';
testExpand {a => 'foo', b => 30, c => 'buzz'}, [qw(d a b)], undef;


done_testing();

