use strict;
use warnings;
use Test::More;
use Test::Builder;
use Test::MockObject;
use Test::Exception;
use DateTime::TimeZone;
use List::Util qw(min);
use FindBin;
use lib ("$FindBin::RealBin/lib");
use BusyBird::Test::Input_Twitter qw(:all);
use BusyBird::Log;
use JSON;
use utf8;

BEGIN {
    use_ok('BusyBird::Input::Twitter');
}

$BusyBird::Log::Logger = undef;

sub test_mock {
    my ($param, $exp_ids, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is_deeply(main->mock_timeline($param), [statuses(@$exp_ids)], $msg);
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

{
    note('--- transforms');
    my $tmock = Test::MockObject->new;
    my $apiurl = 'http://hoge.com/';
    $tmock->mock($_, \&mock_timeline) foreach qw(home_timeline);
    $tmock->mock('search', \&mock_search);
    $tmock->mock('-apiurl', sub { $apiurl });
    my $bbin = BusyBird::Input::Twitter->new(
        backend => $tmock, page_next_delay => 0,
    );
    is_deeply(
        $bbin->transform_status_id({ id => 10, in_reply_to_status_id => 55}),
        {
            id => "${apiurl}statuses/show/10.json",
            in_reply_to_status_id => "${apiurl}statuses/show/55.json",
            busybird => { original => {
                id => 10, in_reply_to_status_id => 55
            } }
        },
        "transform_status_id"
    );
    is_deeply(
        $bbin->transform_search_status({
            id => 10, from_user_id => 88, from_user => "hoge",
            created_at => 'Thu, 06 Oct 2011 19:36:17 +0000'
        }),
        {
            id => 10, user => {
                id => 88,
                screen_name => "hoge"
            },
            created_at => 'Thu Oct 06 19:36:17 +0000 2011'
        },
        "transform_search_status"
    );
    is_deeply(
        $bbin->transformer_default([decode_json(q{
{
            "id": 5, "id_str": "5", "created_at": "Wed, 05 Dec 2012 14:09:11 +0000",
            "in_reply_to_status_id": 12, "in_reply_to_status_id_str": "12",
            "from_user": "foobar",
            "from_user_id": 100,
            "from_user_id_str": "100",
            "true_flag": true,
            "false_flag": false,
            "null_value": null
        }
})]),
        [{
            id => "${apiurl}statuses/show/5.json", id_str => "${apiurl}statuses/show/5.json",
            in_reply_to_status_id => "${apiurl}statuses/show/12.json",
            in_reply_to_status_id_str => "${apiurl}statuses/show/12.json",
            created_at => "Wed Dec 05 14:09:11 +0000 2012",
            true_flag => JSON::true,
            false_flag => JSON::false,
            null_value => undef,
            user => {
                screen_name => "foobar",
                id => 100,
                id_str => "100"
            },
            busybird => {
                original => {
                    id => 5,
                    id_str => "5",
                    in_reply_to_status_id => 12,
                    in_reply_to_status_id_str => "12",
                }
            }
        }],
        'transformer_default'
    );
}

{
    note('--- apiurl option');
    my $apiurl = 'https://foobar.co.jp';
    my $apiurlmock = Test::MockObject->new;
    $apiurlmock->mock('apiurl', sub { $apiurl });
    foreach my $newarg (
        {label => "apiurl option", args => [backend => {}, apiurl => $apiurl]},
        {label => 'only apiurl option', args => [apiurl => $apiurl]},
        {label => "backend apiurl field", args => [backend => {apiurl => $apiurl}]},
        {label => "apiurl option and backend field", args => [backend => {apiurl => "http://hogege.com"}, apiurl => $apiurl]},
        {label => "backend apiurl method", args => [backend => $apiurlmock]}
    ) {
        my $bbin = new_ok('BusyBird::Input::Twitter', $newarg->{args});
        my $label = $newarg->{label};
        is_deeply(
            $bbin->transform_status_id({id => 109}),
            {
                id => "http://foobar.co.jp/statuses/show/109.json",
                busybird => { original => {
                    id => 109
                }}
            },
            "$label: transform_status_id ok"
        );
    }
    my $noapiurl_mock = Test::MockObject->new;
    foreach my $newarg (
        {label => "no apiurl field", args => [backend => []]},
        {label => "no apiurl method", args => [backend => $noapiurl_mock]}
    ) {
        my $bbin = new_ok('BusyBird::Input::Twitter', $newarg->{args});
        my $label = $newarg->{label};
        my $status = { id => 100, user => {screen_name => "foobar"} };
        throws_ok { $bbin->transform_status_id($status) } qr{cannot determine api url}i, "$label ok";
    }
}

{
    note("--- transform_html_unescape");
    my $bbin = new_ok('BusyBird::Input::Twitter', [apiurl => 'hoge']);
    foreach my $case (
        {label => "without entities", in_status => {
            text => '&amp; &lt; &gt; &amp; &quot;',
        }, out_status => {
            text => q{& < > & "},
        }},
            
        {label => "with entities", in_status => {
            'text' => q{&lt;http://t.co/3Rh1Zcymvo&gt; " #test " $GOOG てすと&amp;hearts; ' @debug_ito '},
            'entities' => {
                'hashtags' => [ { 'text' => 'test', 'indices' => [33, 38] }],
                'user_mentions' => [ { 'indices' => [65,75], 'screen_name' => 'debug_ito' } ],
                'symbols' => [ { 'text' => 'GOOG', 'indices' => [41, 46] } ],
                'urls' => [ { 'url' => 'http://t.co/3Rh1Zcymvo', 'indices' => [4, 26] } ]
            },
        }, out_status => {
            text => q{<http://t.co/3Rh1Zcymvo> " #test " $GOOG てすと&hearts; ' @debug_ito '},
            'entities' => {
                'hashtags' => [ { 'text' => 'test', 'indices' => [27, 32] }],
                'user_mentions' => [ { 'indices' => [55,65], 'screen_name' => 'debug_ito' } ],
                'symbols' => [ { 'text' => 'GOOG', 'indices' => [35, 40] } ],
                'urls' => [ { 'url' => 'http://t.co/3Rh1Zcymvo', 'indices' => [1, 23] } ],
            },
        }},
        
        {label => "with retweets", in_status => {
            'text' => 'RT @slashdot: Quadcopter Guided By Thought &amp;mdash; Accurately http://t.co/reAljIdd89',
            'entities' => {
                'hashtags' => [],
                'user_mentions' => [ {'screen_name' => 'slashdot',  'indices' => [3,12] } ],
                'symbols' => [],
                'urls' => [ { 'url' => 'http://t.co/reAljIdd89', 'indices' => [66,88] } ],
            },
            retweeted_status => {
                'text' => 'Quadcopter Guided By Thought &amp;mdash; Accurately http://t.co/reAljIdd89',
                'entities' => {
                    'hashtags' => [],
                    'user_mentions' => [],
                    'symbols' => [],
                    'urls' => [ { 'url' => 'http://t.co/reAljIdd89', 'indices' => [52,74]} ],
                },
            },
        }, out_status => {
            text => 'RT @slashdot: Quadcopter Guided By Thought &mdash; Accurately http://t.co/reAljIdd89',
            'entities' => {
                'hashtags' => [],
                'user_mentions' => [ {'screen_name' => 'slashdot',  'indices' => [3,12] } ],
                'symbols' => [],
                'urls' => [ { 'url' => 'http://t.co/reAljIdd89', 'indices' => [62,84] } ],
            },
            retweeted_status => {
                'text' => 'Quadcopter Guided By Thought &mdash; Accurately http://t.co/reAljIdd89',
                'entities' => {
                    'hashtags' => [],
                    'user_mentions' => [],
                    'symbols' => [],
                    'urls' => [ { 'url' => 'http://t.co/reAljIdd89', 'indices' => [48,70]} ],
                },
            },
        }}
    ) {
        is_deeply($bbin->transform_html_unescape($case->{in_status}), $case->{out_status}, "$case->{label}: HTML unescape OK");
    }
}

my $mocknt = mock_twitter();

note('--- iteration by user_timeline');
my $bbin = BusyBird::Input::Twitter->new(
    backend => $mocknt, page_next_delay => 0, page_max => 500,
    transformer => \&negative_id_transformer,
);
is_deeply(
    $bbin->user_timeline({since_id => 10, screen_name => "someone"}),
    [statuses -100 .. -11],
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
    [statuses -100..-71],
    "user_timeline no since_id"
);
test_call $mocknt, 'user_timeline', {user_id => 1919, count => 30};
end_call $mocknt;

$mocknt->clear;
is_deeply(
    $bbin->user_timeline({max_id => 50, count => 25}),
    [statuses -50..-26],
    "user_timeline max_id"
);
test_call $mocknt, 'user_timeline', {count => 25, max_id => 50};
end_call $mocknt;

$mocknt->clear;
is_deeply(
    $bbin->user_timeline({max_id => 20, since_id => 5, count => 5}),
    [statuses -20..-6],
    "user_timeline max_id and since_id"
);
test_call $mocknt, 'user_timeline', {count => 5, max_id => 20, since_id => 5};
test_call $mocknt, 'user_timeline', {count => 5, max_id => 16, since_id => 5};
test_call $mocknt, 'user_timeline', {count => 5, max_id => 12, since_id => 5};
test_call $mocknt, 'user_timeline', {count => 5, max_id => 8, since_id => 5};
test_call $mocknt, 'user_timeline', {count => 5, max_id => 6, since_id => 5};
end_call $mocknt;

$bbin = BusyBird::Input::Twitter->new(
    backend => $mocknt, page_next_delay => 0, page_max => 2,
    transformer => \&negative_id_transformer
);
$mocknt->clear;
is_deeply(
    $bbin->user_timeline({since_id => 5, screen_name => "foo"}),
    [statuses -100..-82],
    "page_max option"
);
test_call $mocknt, 'user_timeline', {screen_name => "foo", since_id => 5};
test_call $mocknt, 'user_timeline', {screen_name => "foo", since_id => 5, max_id => 91};
end_call $mocknt;

$bbin = BusyBird::Input::Twitter->new(
    backend => $mocknt, page_next_delay => 0, page_max_no_since_id => 3,
    transformer => \&negative_id_transformer
);
$mocknt->clear;
is_deeply(
    $bbin->user_timeline({max_id => 80, count => 11}),
    [statuses -80..-50],
    "page_max_no_since_id option"
);
test_call $mocknt, 'user_timeline', {count => 11, max_id => 80};
test_call $mocknt, 'user_timeline', {count => 11, max_id => 70};
test_call $mocknt, 'user_timeline', {count => 11, max_id => 60};
end_call $mocknt;

$bbin = BusyBird::Input::Twitter->new(
    backend => $mocknt, page_next_delay => 0,
    transformer => \&negative_id_transformer
);
foreach my $method_name (qw(home_timeline list_statuses search favorites mentions retweets_of_me)) {
    note("--- iteration by $method_name");
    $mocknt->clear;
    is_deeply(
        $bbin->$method_name({max_id => 40, since_id => 5, count => 20}),
        [statuses -40..-6],
        "$method_name iterates"
    );
    test_call $mocknt, $method_name, {count => 20, since_id => 5, max_id => 40};
    test_call $mocknt, $method_name, {count => 20, since_id => 5, max_id => 21};
    test_call $mocknt, $method_name, {count => 20, since_id => 5, max_id => 6};
    end_call $mocknt;
}

note('--- public_statuses should never iterate');
$bbin = BusyBird::Input::Twitter->new(
    backend => $mocknt, page_next_delay => 0, page_max_no_since_id => 10,
    transformer => \&negative_id_transformer
);
$mocknt->clear;
is_deeply(
    $bbin->public_timeline(),
    [statuses -100..-91],
    "public_timeline does not iterate even if page_max_no_since_id > 1"
);
test_call $mocknt, 'public_timeline', {};
end_call $mocknt;

{
    note('--- it should return undef if backend throws an exception.');
    my $diemock = Test::MockObject->new;
    my $call_count = 0;
    my @log = ();
    local $BusyBird::Log::Logger = sub { push(@log, [@_]) };
    $diemock->mock('user_timeline', sub {
        my ($self, $params) = @_;
        $call_count++;
        if($call_count == 1) {
            return mock_timeline($self, $params);
        }else {
            die "Some network error.";
        }
    });
    my $diein = BusyBird::Input::Twitter->new(
        backend => $diemock, page_next_delay => 0,
        transformer => \&negative_id_transformer,
    );
    my $result;
    lives_ok { $result = $diein->user_timeline({screen_name => 'hoge', since_id => 10, count => 5}) } '$diein should not throw exception even if backend does.';
    ok(!defined($result), "the result should be undef then.") or diag("result is $result");
    cmp_ok(scalar(grep {$_->[0] =~ /err/} @log), ">=", 1, "at least 1 error reported.");
}

{
    note('--- call timeline method with no backend');
    my @log = ();
    local $BusyBird::Log::Logger = sub { push(@log, [@_]) };
    my $bbin = new_ok('BusyBird::Input::Twitter', [
        apiurl => 'http://fake.com/',
        page_next_delay => 0,
    ]);
    my $result;
    lives_ok { $result = $bbin->user_timeline({screen_name => 'hoge'}) } 'calling user_timeline without backend should not throw exception.';
    ok(!defined($result), 'the result should be undef then');
    cmp_ok(scalar(grep {$_->[0] =~ /err/} @log), ">=", 1, "at least 1 error reported.");
}


done_testing();
