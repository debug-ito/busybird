use strict;
use warnings;
use Test::More;
use BusyBird::Util qw(future_of);
use Test::MockObject;

note('tests for BusyBird::Util::future_of()');

sub create_futurizable_mock {
    my $mock = Test::MockObject->new();
    my $pending_callback;
    $mock->mock('success_result', sub {
        my ($self, %args) = @_;
        $args->{callback}->(undef, 1, 2, 3);
    });
    $mock->mock('failure_result', sub {
        my ($self, %args) = @_;
        $args->{callback}->('failure', 'detailed', 'reason');
    });
    $mock->mock('die', sub {
        die "fatal error";
    });
    $mock->mock('pend_this', sub {
        my ($self, %args) = @_;
        $pending_callback = $args{callback};
    });
    $mock->mock('fire', sub {
        my ($self, @args) = @_;
        $pending_callback->(@args);
    });
}

{
    note('--- immediate cases');
    my $mock = create_futurizable_mock();
    foreach my $case (
        {label => "success result", method => 'success_result', in_args => [foo => 'bar'],
         exp_result_type => 'fulfill', exp_result => [1,2,3]},
        {label => 'failure result', method => 'failure_result', in_args => [],
         exp_result_type => 'reject', exp_result => ['failure', 1]},
        {label => 'die', method => 'die', in_args => [hoge => 10],
         exp_result_type => 'reject', exp_result => ['fatal error']},
    ) {
        note("--- -- case: $case->{label}");
        my $f = future_of($mock, $case->{method}, @{$case->{in_args}});
        isa_ok($f, 'Future::Q', 'result of future_of()');
        ok($f->is_ready, 'f is ready');
        my @got_result;
        my $got_result_type;
        $f->then(sub {
            @got_result = @_;
            $got_result_type = 'fulfill';
        }, sub {
            @got_result = @_;
            $got_result_type = 'reject';
        });
        is($got_result_type, $case->{exp_result_type}, "result type should be $case->{exp_result_type}");
        is_deeply(\@got_result, $case->{exp_result}, "result OK");
    }
}

{
    note('--- failure cases');
    my $mock = create_futurizable_mock();
    foreach my $case (
        {label => 'non existent method',
         in_invocant => $mock, in_method => 'non_existent_method',
         exp_failure => qr/no such method/i},
        {label => 'undef method',
         in_invocant => $mock, in_method => undef,
         exp_failure => qr/method parameter is mandaotry/i},
        {label => "non-object invocant",
         in_invocant => 'plain string', in_method => 'hoge',
         exp_failure => qr/not blessed/i},
        {label => "undef invocant",
         in_invocant => undef, in_method => undef,
         exp_failure => qr/invocant parameter is mandatory/i},
    ) {
        note("--- -- case: $case->{label}");
        my $f = future_of($case->{in_invocant}, $case->{in_method});
        isa_ok($f, "Future::Q");
        ok($f->is_rejected, 'f should be rejected');
        my @result;
        $f->catch(sub { @result = @_ });
        is(scalar(@result), 1, "1 result element");
        like($result->[0], $case->{exp_failure}, "failure message OK");
    }
}


fail("TODO: pending cases");

done_testing();

