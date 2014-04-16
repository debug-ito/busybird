use strict;
use warnings;
use Test::More;
use JSON;
use utf8;

BEGIN {
    use_ok('BusyBird::Filter::Twitter');
}

{
    note('--- transforms');
    my $default_apiurl = "https://api.twitter.com/1.1/"
    is_deeply(
        filter_twitter_status_id()->([{ id => 10, in_reply_to_status_id => 55}]),
        [{
            id => "${default_apiurl}statuses/show/10.json",
            in_reply_to_status_id => "${default_apiurl}statuses/show/55.json",
            busybird => { original => {
                id => 10, in_reply_to_status_id => 55
            } }
        }],
        "status id"
    );
    is_deeply(
        filter_twitter_search_status()->([{
            id => 10, from_user_id => 88, from_user => "hoge",
            created_at => 'Thu, 06 Oct 2011 19:36:17 +0000'
        }]),
        [{
            id => 10, user => {
                id => 88,
                screen_name => "hoge"
            },
            created_at => 'Thu Oct 06 19:36:17 +0000 2011'
        }],
        "search status"
    );
    is_deeply(
        filter_twitter_all()->([decode_json(q{
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
            id => "${default_apiurl}statuses/show/5.json", id_str => "${default_apiurl}statuses/show/5.json",
            in_reply_to_status_id => "${default_apiurl}statuses/show/12.json",
            in_reply_to_status_id_str => "${default_apiurl}statuses/show/12.json",
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
        "all"
    );
}

{
    note('--- apiurl option');
    my $apiurl = 'https://foobar.co.jp';
    foreach my $label (qw(status_id all)) {
        no strict "refs";
        my $func = \&{"filter_twitter_$label"};
        is_deeply(
            $func->($apiurl)->([{id => 109}]),
            [{
                id => "http://foobar.co.jp/statuses/show/109.json",
                busybird => { original => {
                    id => 109
                }}
            }],
            "$label: apiurl option ok"
        );
    }
}

{
    note("--- transform_html_unescape");
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
        is_deeply(filter_twitter_unescape()->([$case->{in_status}]),
                  [$case->{out_status}],
                  "$case->{label}: HTML unescape OK");
    }
}

done_testing();
