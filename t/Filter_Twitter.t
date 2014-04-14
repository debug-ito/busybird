use strict;
use warnings;
use Test::More;
use Test::Builder;
use Test::MockObject;
use Test::Exception;
use DateTime::TimeZone;
use List::Util qw(min);
use JSON;
use utf8;

BEGIN {
    use_ok('BusyBird::Filter::Twitter');
}

fail("review and fix the tests");

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

        {label => '&amp; should be unescaped at the last', in_status => {
            text => '&amp;gt; &amp;lt; &amp;amp; &amp;quot;'
        }, out_status => {
            text => q{&gt; &lt; &amp; &quot;}
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



done_testing();
