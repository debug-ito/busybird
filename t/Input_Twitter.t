use strict;
use warnings;
use Test::More;
use Test::Builder;
use Test::MockObject;
use List::Util qw(min);

BEGIN {
    use_ok('App::BusyBird::Input::Twitter');
}

sub limit {
    my ($orig, $min, $max) = @_;
    $$orig = $min if $$orig < $min;
    $$orig = $max if $$orig > $max;
}

sub mockTimeline {
    my ($self, $params) = @_;
    my $page_size = $params->{count} || $params->{per_page} || $params->{rpp} || 10;
    my $max_id = $params->{max_id} || 100;
    my $since_id = $params->{since_id} || 0;
    limit \$max_id,   1, 100;
    limit \$since_id, 0, 100;
    my @result = ();
    for(my $id = $max_id ; $id > $since_id && int(@result) < $page_size ; $id--) {
        push(@result, { id => $id });
    }
    return \@result;
}

sub statuses {
    my (@ids) = @_;
    return map { +{id => $_} } @ids;
}

sub testMock {
    my ($param, $exp_ids, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is_deeply(main->mockTimeline($param), [statuses(@$exp_ids)], $msg);
}

note('--- test the mock itself');

testMock {}, [100,99,98,97,96,95,94,93,92,91], "mock no param";
testMock {count => 4}, [100,99,98,97], "mock count";
testMock {per_page => 13}, [100,99,98,97,96,95,94,93,92,91,90,89,88], "mock per_page";
testMock {rpp => 150}, [reverse(1..100)], "mock rpp";
testMock {max_id => 50}, [reverse(41..50)], "mock max_id";
testMock {max_id => 120}, [reverse(91..100)], "mock max_id too large";
testMock {max_id => -40}, [1], "mock max_id negative";
testMock {since_id => 95}, [reverse(96 .. 100)], "mock since_id";
testMock {since_id => 120}, [], "mock since_id too large";
testMock {since_id => -100}, [reverse(91..100)], "mock since_id negative";
testMock {max_id => 40, since_id => 35}, [reverse(36..40)], "mock max_id and since_id";
testMock {max_id => 20, since_id => 20}, [], "mock max_id == since_id";

my $mocknt = Test::MockObject->new();
$mocknt->mock($_, \&mockTimeline) foreach qw(home_timeline user_timeline public_timeline list_statuses);

my $bbin = App::BusyBird::Input::Twitter->new(backend => $mocknt, logger => undef);
is_deeply(
    $bbin->user_timeline("label", {since_id => 10}),
    [statuses reverse 11..100],
    "home_timeline since_id"
);

## ファイル出力のテストはテスト環境依存(ファイルシステムとか)なので、AUTHOR_TESTINGにするといいかも。


done_testing();
