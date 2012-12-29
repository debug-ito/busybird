use strict;
use warnings;
use Test::More;
use Test::Builder;
use Test::MockObject;
use Test::Exception;
use List::Util qw(min);

BEGIN {
    use_ok('App::BusyBird::Input::Twitter');
}

sub limit {
    my ($orig, $min, $max) = @_;
    $$orig = $min if $$orig < $min;
    $$orig = $max if $$orig > $max;
}

sub mock_timeline {
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

sub mock_search {
    my ($self, $params) = @_;
    my $statuses = mock_timeline($self, $params);
    return { results => $statuses };
}

sub statuses {
    my (@ids) = @_;
    return map { +{id => $_} } @ids;
}

sub test_mock {
    my ($param, $exp_ids, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is_deeply(main->mock_timeline($param), [statuses(@$exp_ids)], $msg);
}

sub test_call {
    my ($mock, $method, @method_args) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is_deeply([$mock->next_call], [$method, [$mock, @method_args]], "mock method $method");
}

sub end_call {
    my ($mock, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    ok(!defined(scalar($mock->next_call)), $msg || "call end");
}

note('--- test the mock itself');

test_mock {}, [100,99,98,97,96,95,94,93,92,91], "mock no param";
test_mock {count => 4}, [100,99,98,97], "mock count";
test_mock {per_page => 13}, [100,99,98,97,96,95,94,93,92,91,90,89,88], "mock per_page";
test_mock {rpp => 150}, [reverse(1..100)], "mock rpp";
test_mock {max_id => 50}, [reverse(41..50)], "mock max_id";
test_mock {max_id => 120}, [reverse(91..100)], "mock max_id too large";
test_mock {max_id => -40}, [1], "mock max_id negative";
test_mock {since_id => 95}, [reverse(96 .. 100)], "mock since_id";
test_mock {since_id => 120}, [], "mock since_id too large";
test_mock {since_id => -100}, [reverse(91..100)], "mock since_id negative";
test_mock {max_id => 40, since_id => 35}, [reverse(36..40)], "mock max_id and since_id";
test_mock {max_id => 20, since_id => 20}, [], "mock max_id == since_id";

my $mocknt = Test::MockObject->new();
$mocknt->mock($_, \&mock_timeline) foreach qw(home_timeline user_timeline public_timeline list_statuses);
$mocknt->mock('search', \&mock_search);

note('--- iteration by user_timeline');
my $bbin = App::BusyBird::Input::Twitter->new(backend => $mocknt, page_next_delay => 0, page_max => 500, logger => undef);
is_deeply(
    $bbin->user_timeline({since_id => 10, screen_name => "someone"}),
    [statuses reverse 11..100],
    "user_timeline since_id"
);
test_call $mocknt, 'user_timeline', {screen_name => "someone", since_id => 10};
test_call $mocknt, 'user_timeline', {screen_name => "someone", since_id => 10, max_id => 91};
test_call $mocknt, 'user_timeline', {screen_name => "someone", since_id => 10, max_id => 82};
test_call $mocknt, 'user_timeline', {screen_name => "someone", since_id => 10, max_id => 73};
test_call $mocknt, 'user_timeline', {screen_name => "someone", since_id => 10, max_id => 64};
test_call $mocknt, 'user_timeline', {screen_name => "someone", since_id => 10, max_id => 55};
test_call $mocknt, 'user_timeline', {screen_name => "someone", since_id => 10, max_id => 46};
test_call $mocknt, 'user_timeline', {screen_name => "someone", since_id => 10, max_id => 37};
test_call $mocknt, 'user_timeline', {screen_name => "someone", since_id => 10, max_id => 28};
test_call $mocknt, 'user_timeline', {screen_name => "someone", since_id => 10, max_id => 19};
test_call $mocknt, 'user_timeline', {screen_name => "someone", since_id => 10, max_id => 11};
end_call $mocknt;

$mocknt->clear;
is_deeply(
    $bbin->user_timeline({user_id => 1919, count => 30}),
    [statuses reverse 71..100],
    "user_timeline no since_id"
);
test_call $mocknt, 'user_timeline', {user_id => 1919, count => 30};
end_call $mocknt;

$mocknt->clear;
is_deeply(
    $bbin->user_timeline({max_id => 50, count => 25}),
    [statuses reverse 26..50],
    "user_timeline max_id"
);
test_call $mocknt, 'user_timeline', {count => 25, max_id => 50};
end_call $mocknt;

$mocknt->clear;
is_deeply(
    $bbin->user_timeline({max_id => 20, since_id => 5, count => 5}),
    [statuses reverse 6..20],
    "user_timeline max_id and since_id"
);
test_call $mocknt, 'user_timeline', {count => 5, max_id => 20, since_id => 5};
test_call $mocknt, 'user_timeline', {count => 5, max_id => 16, since_id => 5};
test_call $mocknt, 'user_timeline', {count => 5, max_id => 12, since_id => 5};
test_call $mocknt, 'user_timeline', {count => 5, max_id => 8, since_id => 5};
test_call $mocknt, 'user_timeline', {count => 5, max_id => 6, since_id => 5};
end_call $mocknt;

$bbin = App::BusyBird::Input::Twitter->new(backend => $mocknt, page_next_delay => 0, page_max => 2, logger => undef);
$mocknt->clear;
is_deeply(
    $bbin->user_timeline({since_id => 5, screen_name => "foo"}),
    [statuses reverse 82..100],
    "page_max option"
);
test_call $mocknt, 'user_timeline', {screen_name => "foo", since_id => 5};
test_call $mocknt, 'user_timeline', {screen_name => "foo", since_id => 5, max_id => 91};
end_call $mocknt;

$bbin = App::BusyBird::Input::Twitter->new(backend => $mocknt, page_next_delay => 0, page_max_no_since_id => 3, logger => undef);
$mocknt->clear;
is_deeply(
    $bbin->user_timeline({max_id => 80, count => 11}),
    [statuses reverse 50..80],
    "page_max_no_since_id option"
);
test_call $mocknt, 'user_timeline', {count => 11, max_id => 80};
test_call $mocknt, 'user_timeline', {count => 11, max_id => 70};
test_call $mocknt, 'user_timeline', {count => 11, max_id => 60};
end_call $mocknt;

$bbin = App::BusyBird::Input::Twitter->new(backend => $mocknt, page_next_delay => 0, logger => undef);
foreach my $method_name (qw(home_timeline list_statuses search)) {
    note("--- iteration by $method_name");
    $mocknt->clear;
    is_deeply(
        [map { $_->{id} } @{$bbin->$method_name({max_id => 40, since_id => 5, count => 20})}],
        [reverse 6..40],
        "$method_name iterates"
    );
    test_call $mocknt, $method_name, {count => 20, since_id => 5, max_id => 40};
    test_call $mocknt, $method_name, {count => 20, since_id => 5, max_id => 21};
    test_call $mocknt, $method_name, {count => 20, since_id => 5, max_id => 6};
    end_call $mocknt;
}

note('--- public_statuses should never iterate');
$bbin = App::BusyBird::Input::Twitter->new(backend => $mocknt, page_next_delay => 0, page_max_no_since_id => 10, logger => undef);
$mocknt->clear;
is_deeply(
    $bbin->public_timeline(),
    [statuses reverse 91..100],
    "public_timeline does not iterate even if page_max_no_since_id > 1"
);
test_call $mocknt, 'public_timeline', {};
end_call $mocknt;

{
    my $diemock = Test::MockObject->new;
    my $call_count = 0;
    $diemock->mock('user_timeline', sub {
        my ($self, $params) = @_;
        $call_count++;
        if($call_count == 1) {
            return mock_timeline($self, $params);
        }else {
            die "Some network error.";
        }
    });
    my $diein = App::BusyBird::Input::Twitter->new(backend => $diemock, page_next_delay => 0, logger => undef);
    my $result;
    lives_ok { $result = $diein->user_timeline({since_id => 10, count => 5}) } '$diein should not throw exception even if backend does.';
    ok(!defined($result), "the result should be undef then.") or diag("result is $result");
}

if(!$ENV{AUTHOR_TEST}) {
    note("Set AUTHOR_TEST env to do some more tests.");
}else {
    my $filename = "test_persistence_file_input_twitter";
    if(-r $filename) {
        unlink($filename) or die "Cannot remove $filename: $!";
    }
    my $bbin = App::BusyBird::Input::Twitter->new(
        backend => $mocknt, filepath => $filename, page_next_delay => 0, logger => undef
    );
    $mocknt->clear;
    is_deeply(
        $bbin->user_timeline({max_id => 30, since_id => 5, count => 20, user_id => 88}),
        [statuses reverse 6..30],
        "user_timeline: init"
    );
    test_call $mocknt, 'user_timeline', {user_id => 88, count => 20, since_id => 5, max_id => 30};
    test_call $mocknt, 'user_timeline', {user_id => 88, count => 20, since_id => 5, max_id => 11};
    test_call $mocknt, 'user_timeline', {user_id => 88, count => 20, since_id => 5, max_id => 6};
    end_call $mocknt;
    
    ok(-r $filename, "$filename created");

    $mocknt->clear;
    is_deeply(
        $bbin->user_timeline({max_id => 70, count => 35, user_id => 88}),
        [statuses reverse 31..70],
        "user_timmeline: from the previous max_id"
    );
    test_call $mocknt, 'user_timeline', {user_id => 88, count => 35, since_id => 30, max_id => 70};
    test_call $mocknt, 'user_timeline', {user_id => 88, count => 35, since_id => 30, max_id => 36};
    test_call $mocknt, 'user_timeline', {user_id => 88, count => 35, since_id => 30, max_id => 31};
    end_call $mocknt;

    $mocknt->clear;
    is_deeply(
        $bbin->user_timeline({count => 5, screen_name => "hoge"}),
        [statuses reverse 96..100],
        "user_timeline: different label"
    );
    test_call $mocknt, "user_timeline", {count => 5, screen_name => 'hoge'};
    end_call $mocknt;

    ok(-r $filename, "$filename exists");
    unlink($filename);

    ## what if search in UTF8?? is $label OK?
}


fail("--- TODO: transformer option.");



done_testing();
