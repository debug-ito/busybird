
use strict;
use warnings;

use Test::More;
use Test::Exception;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use Pseudo::CV;

BEGIN {
    use_ok('BusyBird::Defer::Queue');
}


sub test_messages {
    my ($got, @expected) = @_;
    is(int(@$got), int(@expected), "number of messages");
    foreach my $i (0 .. $#expected) {
        is($got->[$i], $expected[$i], "message : " . $expected[$i]);
    }
}

sub delay_msg_statement {
    my ($result) = @_;
    return sub {
        my ($d, $delay, $msg) = @_;
        my $w; $w = PCVtimer $delay, 0, sub {
            undef $w;
            note($msg);
            push(@$result, $msg);
            $d->done($delay, $msg);
        };
    };
}

sub shift_delay_msg_statement {
    my ($result) = @_;
    return sub {
        my ($d, $delays, $msg) = @_;
        my $delay = shift(@$delays);
        my $remain = int(@$delays);
        my $my_msg = "$msg$remain";
        my $w; $w = PCVtimer $delay, 0, sub {
            undef $w;
            note($my_msg);
            push(@$result, $my_msg);
            $d->done($delays, $msg);
        };
    };
}

sub cv_ender {
    my ($cv) = @_;
    my $d = BusyBird::Defer::Queue->new();
    $d->do(
        sub {
            my ($d) = shift;
            $cv->end();
            $d->done(@_);
        }
    );
    return $d;
}


{
    note('--- only 1 program instance can be run at a time.');
    my $dq = BusyBird::Defer::Queue->new(max_active => 1);
    my $cv = Pseudo::CV->new;
    my @result = ();
    my $end = cv_ender($cv);
    $dq->do(delay_msg_statement(\@result));
    $cv->begin; $dq->run($end->clone, 0.2, "a");
    $cv->begin; $dq->run($end->clone, 0.1, "b");
    $cv->begin; $dq->run($end->clone, 0.2, "c");
    $cv->begin; $dq->run($end->clone, 0.4, "d");
    $cv->begin; $dq->run($end->clone, 0.2, "e");
    $cv->begin; $dq->run($end->clone, 0.3, "f");
    $cv->begin; $dq->run($end->clone, 0.1, "g");
    $cv->begin; $dq->run($end->clone, 0.2, "h");
    $cv->recv;
    test_messages \@result, qw(a b c d e f g h);
}

{
    note('--- 2 program instances can be run concurrently.');
    my $dq = BusyBird::Defer::Queue->new(max_active => 2);
    my $cv = Pseudo::CV->new;
    my @result = ();
    my $end = cv_ender($cv);
    $dq->do(delay_msg_statement(\@result));
    $cv->begin; $dq->run($end->clone, 0.2, "a");
    $cv->begin; $dq->run($end->clone, 0.1, "b");
    $cv->begin; $dq->run($end->clone, 0.2, "c");
    $cv->begin; $dq->run($end->clone, 0.4, "d");
    $cv->begin; $dq->run($end->clone, 0.2, "e");
    $cv->begin; $dq->run($end->clone, 0.3, "f");
    $cv->begin; $dq->run($end->clone, 0.1, "g");
    $cv->begin; $dq->run($end->clone, 0.2, "h");
    $cv->recv;
    test_messages \@result, qw(b a c e d g f h);
}

{
    note('--- Infinite concurrency');
    my $dq = BusyBird::Defer::Queue->new(max_active => 0);
    my $cv = Pseudo::CV->new;
    my @result = ();
    my $end = cv_ender($cv);
    $dq->do(delay_msg_statement(\@result));
    $cv->begin; $dq->run($end->clone, 0.5, 'a');
    $cv->begin; $dq->run($end->clone, 0.4, 'b');
    $cv->begin; $dq->run($end->clone, 0.3, 'c');
    $cv->begin; $dq->run($end->clone, 0.2, 'd');
    $cv->begin; $dq->run($end->clone, 0.1, 'e');
    $cv->begin; $dq->run($end->clone, 0.0, 'f');
    $cv->recv;
    test_messages \@result, qw(f e d c b a);
}

{
    note('--- nested programs (bottle-neck)');
    my $parent = BusyBird::Defer::Queue->new(max_active => 5);
    my $child  = BusyBird::Defer::Queue->new(max_active => 1);
    my $cv = Pseudo::CV->new;
    my @result = ();
    my $end = cv_ender($cv);
    $child->do(shift_delay_msg_statement(\@result));
    $parent->do(shift_delay_msg_statement(\@result));
    $parent->do($child);
    $parent->do(shift_delay_msg_statement(\@result));
    $cv->begin; $parent->run($end->clone, [0.1, 0.5, 0.2], "a");
    $cv->begin; $parent->run($end->clone, [0.2, 0.1, 0.4], "b");
    $cv->begin; $parent->run($end->clone, [0.3, 0.2, 0.4], "c");
    $cv->begin; $parent->run($end->clone, [0.4, 0.5, 0.5], "d");
    $cv->begin; $parent->run($end->clone, [0.5, 0.1, 0.3], "e");
    $cv->begin; $parent->run($end->clone, [0.2, 0.1, 0.1], "f");
    $cv->recv;
    test_messages \@result, qw(a2 b2 c2 d2 e2 a1 b1 a0 c1 f2 b0 c0 d1 e1 f1 f0 e0 d0);
}

{
    note('--- multiple nesting');
    my @ds = map { BusyBird::Defer::Queue->new(max_active => 2) } 0..3;
    my @result = ();
    my $cv = Pseudo::CV->new;
    my $end = cv_ender($cv);
    foreach my $i (0..2) {
        $ds[$i]->do(shift_delay_msg_statement(\@result));
        $ds[$i]->do($ds[$i + 1]);
    }
    $ds[3]->do(shift_delay_msg_statement(\@result));
    $cv->begin; $ds[0]->run($end->clone, [0.2, 0.1, 0.1, 0.2], "a");
    $cv->begin; $ds[0]->run($end->clone, [0.1, 0.4, 0.3, 0.2], "b");
    $cv->begin; $ds[0]->run($end->clone, [0.1, 0.2, 0.2, 0.2], "c");
    $cv->begin; $ds[0]->run($end->clone, [0.2, 0.2, 0.1, 0.1], "d");
    $cv->recv;
    test_messages \@result, qw(b3 a3 a2 a1 b2 a0 c3 b1 c2 b0 c1 d3 c0 d2 d1 d0);
}

{
    note('--- cascading');
    my $pd = BusyBird::Defer::Queue->new(max_active => 0);
    my @ds = map { BusyBird::Defer::Queue->new(max_active => 2) } 0..3;
    my @result = ();
    my $cv = Pseudo::CV->new;
    my $end = cv_ender($cv);
    foreach my $cd (@ds) {
        $cd->do(shift_delay_msg_statement(\@result));
        $pd->do($cd);
    }
    $cv->begin; $pd->run($end->clone, [0.3, 0.2, 0.9, 0.2], "a");
    $cv->begin; $pd->run($end->clone, [0.2, 0.4, 0.2, 0.1], "b");
    $cv->begin; $pd->run($end->clone, [0.2, 0.5, 0.2, 0.3], "c");
    $cv->begin; $pd->run($end->clone, [0.4, 0.4, 0.1, 0.3], "d");
    $cv->recv;
    test_messages \@result, qw(b3 a3 c3 a2 b2 d3 b1 b0 c2 d2 c1 d1 a1 c0 d0 a0);
}

{
    note('--- while');
    my $d = BusyBird::Defer::Queue->new(max_active => 1);
    my @result = ();
    my $cv = Pseudo::CV->new;
    $d->do(
        sub {
            my ($d, $label) = @_;
            $d->{label} = $label;
            $d->done;
        }
    );
    $d->while(sub { shift->iter() <= 5 });
    $d->do(
        sub {
            my ($d) = @_;
            my $w; $w = PCVtimer 0.02, 0, sub {
                undef $w;
                my $msg = sprintf("%s%d", $d->{label}, $d->iter);
                note($msg);
                push(@result, $msg);
                $d->done;
            };
        }
    );
    $d->end_while();
    $d->do(sub { $cv->end; shift->done });
    $cv->begin; $d->run(undef, 'a');
    $cv->begin; $d->run(undef, 'b');
    $cv->recv;
    test_messages \@result, qw(a1 a2 a3 a4 a5 b1 b2 b3 b4 b5);
}

{
    note('--- if');
    my $d = BusyBird::Defer::Queue->new();
    my @result = ();
    my $cv = Pseudo::CV->new();
    $d->{parent_msg} = "p";
    $d->do(
        sub {
            my ($d, $label) = @_;
            note($d->{parent_msg});
            push(@result, $d->{parent_msg});
            %$d = ();
            $d->{label} = $label;
            $d->done;
        }
    );
    $d->if(sub { my $d = shift; length($d->{label}) > 1 });
    $d->do(
        sub {
            my $d = shift;
            my $w; $w = PCVtimer 0.01, 0, sub {
                undef $w;
                note("long"); push(@result, "long");
                $d->done;
            };
        }
    );
    $d->else();
    $d->do(
        sub {
            my $d = shift;
            my $w; $w = PCVtimer 0.01, 0, sub {
                undef $w;
                note("short"); push(@result, "short");
                $d->done;
            };
        }
    );
    $d->end_if();
    $d->do(sub { my $d = shift; note($d->{label}); push(@result, $d->{label}); $d->done });
    my $end = cv_ender($cv);
    $cv->begin; $d->run($end->clone, "a");
    $cv->begin; $d->run($end->clone, "bb");
    $cv->begin; $d->run($end->clone, "cc");
    $cv->begin; $d->run($end->clone, "d");
    $cv->recv;
    test_messages \@result, qw(p short a p long bb p long cc p short d);
}

{
    note('--- throw exception (handled in the defer)');
    my $d = BusyBird::Defer::Queue->new(max_active => 0);
    my @result = ();
    my $cv = Pseudo::CV->new();
    $d->try();
    $d->do(shift_delay_msg_statement(\@result));
    $d->do(
        sub {
            my ($d, $delays, $msg) = @_;
            $d->throw([$delays, $msg]);
        }
    );
    $d->catch(
        qr// => sub {
            my ($d, $thrown) = @_;
            my ($delays, $msg) = @$thrown;
            push(@result, "E$msg");
            $d->done($delays, $msg);
        },
        FINALLY => shift_delay_msg_statement(\@result),
    );
    $d->do(sub { $cv->end; shift->done });
    $cv->begin; $d->run(undef, [0.2, 0.1], "a");
    $cv->begin; $d->run(undef, [0.1, 0.3], "b");
    $cv->recv;
    test_messages \@result, qw(b1 Eb a1 Ea a0 b0);
}

{
    note('--- throw exception (handled by parent)');
    my $pd = BusyBird::Defer::Queue->new(max_active => 0);
    my $cd = BusyBird::Defer::Queue->new(max_active => 2);
    my @result = ();
    my $cv = Pseudo::CV->new();
    $pd->try();
    $pd->do($cd);
    $cd->do(shift_delay_msg_statement(\@result));
    $cd->do(
        sub {
            my ($d, $delays, $msg) = @_;
            my $w; $w = PCVtimer shift(@$delays), 0, sub {
                undef $w;
                $d->throw([$delays, $msg]);
            };
        }
    );
    $pd->catch(
        qr// => sub {
            my ($d, $thrown) = @_;
            my ($delays, $msg) = @$thrown;
            my $w; $w = PCVtimer shift(@$delays), 0, sub {
                undef $w;
                my $t_msg = "T$msg";
                note($t_msg); push(@result, $t_msg);
                $d->done($delays, "E$msg");
            };
        },
    );
    $pd->do(shift_delay_msg_statement(\@result));
    my $end = cv_ender($cv);
    $cv->begin; $pd->run($end->clone, [0.2, 0.1, 0.1, 0.3], "a");
    $cv->begin; $pd->run($end->clone, [0.1, 0.1, 0.1, 0.2], "b");
    $cv->begin; $pd->run($end->clone, [0.4, 0.2, 0.3, 0.1], "c");
    $cv->begin; $pd->run($end->clone, [0.5, 0.1, 0.1, 0.3], "d");
    $cv->recv;
    test_messages \@result, qw(b3 a3 Tb Ta Eb0 c3 Ea0 d3 Td Tc Ec0 Ed0);
}

{
    note('--- throw exception (unhandled)');
    my $d = BusyBird::Defer::Queue->new();
    $d->do(sub { $d->throw("I'm dead!") });
    throws_ok { $d->run() } qr/I'm dead/, "Unhandled exception makes it die.";
}

{
    note('--- used as a parent');
    my $pd = BusyBird::Defer::Queue->new(max_active => 1);
    my $cd = BusyBird::Defer::Queue->new(max_active => 0);
    my @result = ();
    my $cv = Pseudo::CV->new();
    $cd->do(shift_delay_msg_statement \@result);
    $pd->do(shift_delay_msg_statement \@result);
    $pd->do(sub { $cv->end; shift->done });
    
    $cv->begin; $cd->run($pd, [0.4, 0.1], "a");
    $cv->begin; $cd->run($pd, [0.3, 0.1], "b");
    $cv->begin; $cd->run($pd, [0.2, 0.1], "c");
    $cv->begin; $cd->run($pd, [0.1, 0.4], "d");
    $cv->recv;
    test_messages \@result, qw(d1 c1 b1 a1 d0 c0 b0 a0);
}

{
    note('--- do_batch');
    my $pd = BusyBird::Defer::Queue->new(max_active => 0);
    my $cd = BusyBird::Defer::Queue->new(max_active => 1);
    my @result = ();
    my $cv = Pseudo::CV->new();
    $cd->do(shift_delay_msg_statement \@result);
    $pd->do( [$cd, $cd, $cd, $cd] );
    $pd->do(
        sub {
            my ($d, @task_results) = @_;
            foreach my $task_result (@task_results) {
                my $msg = $task_result->[1];
                note($msg);
                push(@result, $msg);
            }
            $d->done();
        }
    );
    $pd->do(sub { $cv->end; shift->done });
    eval {
        $cv->begin; $pd->run(undef, [[0.5], "a"], [[0.4], "b"], [[0.3], "c"], [[0.1], "d"]);
        $cv->begin; $pd->run(undef, [[0.1], "e"], [[0.3], "f"], [[0.5], "g"], [[0.1], "h"]);
        $cv->recv;
        test_messages \@result, qw(d0 h0 c0 b0 a0 a b c d e0 f0 g0 e f g h);
    };
    if($@) {
        fail("Something crached");
        diag($@);
    }
}

{
    note('--- mixed (BusyBird::Defer and BusyBird::Defer::Queue) deferred');
    my $dq = BusyBird::Defer::Queue->new(max_active => 1);
    my $cq = BusyBird::Defer->new();
    my @result = ();
    my $cv = Pseudo::CV->new();
    $dq->do(shift_delay_msg_statement \@result);
    $dq->do($cq);
    $cq->do(shift_delay_msg_statement \@result);
    $dq->do(sub { $cv->end; shift->done });
    $cv->begin; $dq->run(undef, [0.2, 0.1], "a");
    $cv->begin; $dq->run(undef, [0.1, 0  ], "b");
    $cv->begin; $dq->run(undef, [0  , 0.2], "c");
    $cv->recv;
    test_messages \@result, qw(a1 a0 b1 b0 c1 c0);
}

{
    note('--- empty deferred');
    my $empty = BusyBird::Defer::Queue->new();
    my $p = BusyBird::Defer->new();
    my @result = ();
    my $cv = Pseudo::CV->new();
    $empty->do(sub { my $d = shift; $d->done(@_) });
    $p->do(
        sub {
            my ($d) = @_;
            my $w; $w = PCVtimer 0.05, 0, sub {
                undef $w;
                push(@result, 'p');
                $d->done();
            };
        }
    );
    $p->do(sub { $cv->send; shift->done });
    $empty->run($p);
    $cv->recv;
    test_messages \@result, qw(p);
}


done_testing();


