use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('BusyBird::Defer::Queue');
}

{
    my @result = ();
    my $p = BusyBird::Defer::Queue->new(max_active => 10);
    $p->do(sub { push(@result, 'P'), shift->done  });
    my $d = $p->deferrize(
        sub { push(@result, 'a'), shift->done },
        BusyBird::Defer->new()->do(
            sub { push(@result, 'b'), shift->done }
        ),
        $p->deferrize(sub { push(@result, 'c'), shift->done }),
    );
    isa_ok($d, 'BusyBird::Defer::Queue', "deferrize() creates another Queue");
    isnt($d, $p, 'deferrize() returns NEW object.');
    is($d->max_active, $p->max_active, "deferreize() preserves max_active");
    @result = ();
    $p->run();
    is_deeply(\@result, ['P'], '$p pushes P');
    @result = ();
    $d->run();
    is_deeply(\@result, [qw(a b c)], '$d does not inherit program from $p. It just pushes a, b, c');
}

done_testing();


