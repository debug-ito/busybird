#!/usr/bin/perl -w

use strict;
use warnings;
use lib 't/lib';

use Test::More;

BEGIN {
    use_ok('JSON');
    use_ok('Test::XML::Simple');
    use_ok('DateTime');
    use_ok('BusyBird::Status');
}

sub testJSON {
    my (@test_statuses) = @_;
    note("--- testJSON");
    cmp_ok((grep { defined($_->{expect_format}{json}) } @test_statuses), "==", int(@test_statuses),
           "All test_statuses have expected JSON entries.");
    my $exp_statuses_json = "[". join(",", map { $_->{expect_format}{json} } @test_statuses) ."]";
    my $json_statuses = BusyBird::Status->format('json', [ map {$_->{status}} @test_statuses ]);
    cmp_ok($json_statuses, 'ne', '');
    my $decoded_got_json = decode_json($json_statuses);
    my $decoded_exp_json = decode_json($exp_statuses_json);
    is_deeply($decoded_got_json, $decoded_exp_json);
}

sub testXML {
    my (@test_statuses) = @_;
    note("--- testXML");
    cmp_ok((grep { defined($_->{expect_format}{xml}) } @test_statuses), '==', int(@test_statuses),
           'All test_statuses have expected XML entries.');
    my $exp_xml = '<statuses type="array">' . join("", map {$_->{expect_format}{xml}} @test_statuses) . "</statuses>";
    
    ## ** Remove unnecessary spaces
    my $replaced = 1;
    while($replaced) {
        $replaced = 0;
        $exp_xml =~ s!>\s+(< *[^/][^>]*>)!>$1!gs and $replaced = 1;
        $exp_xml =~ s!(< */[^>]*>)\s+(< */[^>]*>)!$1$2!gs and $replaced = 1;
        $exp_xml =~ s!/ *>\s+(< */[^>]*>)!/>$1!gs and $replaced = 1;
    }
    
    my $got_xml = BusyBird::Status->format('xml', [ map {$_->{status}} @test_statuses ]);
    xml_valid $got_xml, 'Valid XML document';
    xml_node $got_xml, '/statuses', 'XML node /statuses exists';
    xml_is_deeply $got_xml, '/statuses', $exp_xml, 'XML content is what is expected' or do {
        diag("GOT XML: $got_xml");
        diag("EXP XML: $exp_xml");
        fail('xml_is_deeply failed.');
    };
}

sub testClone {
    my ($test_status) = @_;
    note("--- testClone");
    my $status = $test_status->{status};
    my $clone = $status->clone();
    is_deeply($status, $clone, "clone is exactly the same as the original");
    cmp_ok(DateTime->compare($status->content->{created_at}, $clone->content->{created_at}), "==", 0, "... created_at is exactly the same.");
    my ($orig_id, $orig_id_str) = @{$status->content}{'id', 'id_str'};
    my $orig_screen_name = $status->content->{user}->{screen_name};
    $clone->put(id => "foobar", id_str => "foobar");
    $clone->content->{user}->{screen_name} = "HOGE_SCREEN_NAME";
    is($status->content->{id}, $orig_id, "original and clone is independent (id, original)");
    is($clone->content->{id}, 'foobar',"... (id, clone)");
    is($status->content->{id_str}, $orig_id_str, "... (id_str, original)");
    is($clone->content->{id_str}, 'foobar', "... (id_str, clone)");
    is($status->content->{user}->{screen_name}, $orig_screen_name, "... (user/screen_name, original)");
    is($clone->content->{user}->{screen_name}, "HOGE_SCREEN_NAME", "... (user/screen_name, clone)");
}

sub testSerialize {
    my (@test_statuses) = @_;
    note("--- testSerialize");
    my $statuses = [ map {$_->{status}} @test_statuses ];
    my $serialized = BusyBird::Status->serialize($statuses);
    ok(defined($serialized), "serialize() returns a defined value");
    ok(!ref($serialized), "... and it's a scalar");
    my $des_statuses = BusyBird::Status->deserialize($serialized);
    ok(defined($des_statuses), "deserialize() returns defined value");
    is(ref($des_statuses), 'ARRAY', "... and it's an array ref.");
    is_deeply($des_statuses, $statuses, "statuses are restored perfectly.");
}

BusyBird::Status->setTimeZone('UTC');

my @statuses_for_test = (
    {
        status => new_ok('BusyBird::Status', [
            id => 'hoge',
            id_str => 'hoge',
            created_at => DateTime->new(
                year => 2011, month => 6, day => 14, hour => 10, minute => 45, second => 11, time_zone => '+0900',
            ),
            text => 'foo bar',
            in_reply_to_screen_name => undef,
            user => {
                screen_name => 'screenName',
                name => 'na me',
                profile_image_url => undef,
            },
            busybird => {
                input_name => 'input',
                score => undef,
            }
        ]),
        expect_format => {
            json => qq{
{
    "id": "hoge",
    "id_str": "hoge",
    "created_at": "Tue Jun 14 01:45:11 +0000 2011",
    "text": "foo bar",
    "in_reply_to_screen_name": null,
    "user": {
        "screen_name": "screenName",
        "name": "na me",
        "profile_image_url": null
    },
    "busybird": {
        "input_name": "input",
        "score": null
    }
}
},
            xml => qq{<status>
  <busybird>
    <input_name>input</input_name>
    <score />
  </busybird>
  <created_at>Tue Jun 14 01:45:11 +0000 2011</created_at>
  <id>hoge</id>
  <id_str>hoge</id_str>
  <in_reply_to_screen_name />
  <text>foo bar</text>
  <user>
    <name>na me</name>
    <profile_image_url />
    <screen_name>screenName</screen_name>
  </user>
</status>}
        }
    },
    {
        status => new_ok('BusyBird::Status', [
            id => 99239,
            id_str => '99239',
            created_at => DateTime->new(
                year => 2012, month => 5, day => 20, hour => 12, minute => 22, second => 11, time_zone => '+0900'
            ),
            text => 'some text',
            user => {
                screen_name => 'toshio_ito',
                name => 'Toshio ITO',
                profile_image_url => undef,
            },
            busybird => {
                input_name => "Input",
            },
        ]),
        expect_format => {
            json => qq{
{
    "id": 99239,
    "id_str": "99239",
    "created_at": "Sun May 20 03:22:11 +0000 2012",
    "text": "some text",
    "user": {
        "screen_name": "toshio_ito",
        "name": "Toshio ITO",
        "profile_image_url": null
    },
    "busybird": {
        "input_name": "Input"
    }
}
},
            xml => qq{<status>
  <busybird>
    <input_name>Input</input_name>
  </busybird>
  <created_at>Sun May 20 03:22:11 +0000 2012</created_at>
  <id>99239</id>
  <id_str>99239</id_str>
  <text>some text</text>
  <user>
    <name>Toshio ITO</name>
    <profile_image_url />
    <screen_name>toshio_ito</screen_name>
  </user>
</status>}
        }
    },
    {
        status => new_ok('BusyBird::Status', [
            id => "SomeSource_101105",
            id_str => "SomeSource_101105",
            created_at => DateTime->new(
                year => 2012, month => 4, day => 22, hour => 2, minute => 5, second => 45, time_zone => '-1000',
            ),
            text => 'UTF8 てきすと ',
            user => {
                screen_name => "hogeuser",
                name => "ほげ ユーザ",
                created_at => DateTime->new(
                    year => 2008, month => 11, day => 1, hour => 16, minute => 33, second => 0, time_zone => '+0000',
                ),
            },
            busybird => {
                original => {
                    id => 101105,
                    id_str => "101105",
                    in_reply_to_status_id => undef,
                    in_reply_to_status_id_str => undef,
                }
            },
        ]),
        expect_format => {
            json => qq{
{
    "id": "SomeSource_101105",
    "id_str": "SomeSource_101105",
    "created_at": "Sun Apr 22 12:05:45 +0000 2012",
    "text": "UTF8 てきすと ",
    "user": {
        "screen_name": "hogeuser",
        "name": "ほげ ユーザ",
        "created_at": "Sat Nov 01 16:33:00 +0000 2008"
    },
    "busybird": {
        "original": {
            "id": 101105,
            "id_str": "101105",
            "in_reply_to_status_id": null,
            "in_reply_to_status_id_str": null
        }
    }
}
},
            xml => qq{<status>
  <busybird>
    <original>
      <id>101105</id>
      <id_str>101105</id_str>
      <in_reply_to_status_id />
      <in_reply_to_status_id_str />
    </original>
  </busybird>
  <created_at>Sun Apr 22 12:05:45 +0000 2012</created_at>
  <id>SomeSource_101105</id>
  <id_str>SomeSource_101105</id_str>
  <text>UTF8 てきすと </text>
  <user>
    <created_at>Sat Nov 01 16:33:00 +0000 2008</created_at>
    <name>ほげ ユーザ</name>
    <screen_name>hogeuser</screen_name>
  </user>
</status>}
        }
    },
    {
        status => new_ok('BusyBird::Status', [
            id => "99332",
            id_str => "99332",
            created_at => DateTime->new(
                year => 2009, month => 1, day => 1, hour => 3, minute => 0, second => 0, time_zone => '+0900',
            ),
            user => {
                screen_name => 'tito',
                created_at => DateTime->new(
                    year => 2007, month => 12, day => 31, hour => 22, minute => 6, second => 46, time_zone => '-0500',
                ),
            },
            busybird => {
                original => {
                    id => 9322,
                    id_str => '9322',
                }
            }
        ]),
        expect_format => {
            json => qq{
{
    "id": "99332",
    "id_str": "99332",
    "created_at": "Wed Dec 31 18:00:00 +0000 2008",
    "user": {
        "screen_name": "tito",
        "created_at": "Tue Jan 01 03:06:46 +0000 2008"
    },
    "busybird": {
        "original": {
            "id": 9322,
            "id_str": "9322"
        }
    }
}
},
            xml => qq{<status>
  <busybird>
    <original>
      <id>9322</id>
      <id_str>9322</id_str>
    </original>
  </busybird>
  <created_at>Wed Dec 31 18:00:00 +0000 2008</created_at>
  <id>99332</id>
  <id_str>99332</id_str>
  <user>
    <created_at>Tue Jan 01 03:06:46 +0000 2008</created_at>
    <screen_name>tito</screen_name>
  </user>
</status>}
        }
    },
    {
        status => new_ok('BusyBird::Status', [
            id => "Twitter_http://my.twitter.local/api_200101",
            id_str => "Twitter_http://my.twitter.local/api_200101",
            created_at => DateTime->new(
                year => 2012, month => 2, day => 29, hour => 0, minute => 0, second => 3, time_zone => '-0200',
            ),
            text => "http://foo.com/ http://bar.com/ It's test for \"quotes\" and entities.",
            entities => {
                "urls" => [
                    {
                        "url" => "http://foo.com/",
                        "expanded_url" => "http://www.foo.com/",
                        "indices" => [ 0,  15],
                    },
                    {
                        "url" => "http://bar.com/",
                        "expanded_url" => undef,
                        "indices" => [ 16, 31 ],
                    },
                ]
            },
            busybird => {
                original => {
                    id => 200101,
                    id_str => "200101",
                }
            },
        ]),
        expect_format => {
            json => q{
{
    "id": "Twitter_http://my.twitter.local/api_200101",
    "id_str": "Twitter_http://my.twitter.local/api_200101",
    "created_at": "Wed Feb 29 02:00:03 +0000 2012",
    "text": "http://foo.com/ http://bar.com/ It's test for \"quotes\" and entities.",
    "entities": {
        "urls": [
            {
                "url": "http://foo.com/",
                "expanded_url": "http://www.foo.com/",
                "indices": [ 0,  15]
            },
            {
                "url": "http://bar.com/",
                "expanded_url": null,
                "indices": [ 16, 31 ]
            }
        ]
    },
    "busybird": {
        "original": {
            "id": 200101,
            "id_str": "200101"
        }
    }
}
},
            xml => qq{<status>
  <busybird>
    <original>
      <id>200101</id>
      <id_str>200101</id_str>
    </original>
  </busybird>
  <created_at>Wed Feb 29 02:00:03 +0000 2012</created_at>
  <entities>
    <urls>
      <url start="0" end="15">
        <expanded_url>http://www.foo.com/</expanded_url>
        <url>http://foo.com/</url>
      </url>
      <url start="16" end="31">
        <expanded_url />
        <url>http://bar.com/</url>
      </url>
    </urls>
  </entities>
  <id>Twitter_http://my.twitter.local/api_200101</id>
  <id_str>Twitter_http://my.twitter.local/api_200101</id_str>
  <text>http://foo.com/ http://bar.com/ It&quot;s test for "quotes" and entities.</text>
</status>}
        }
    },
    {
        status => new_ok('BusyBird::Status', [
            id => "RSS_http://some.site.com/feed?format=rss_998223",
            id_str => "RSS_http://some.site.com/feed?format=rss_998223",
            created_at => DateTime->new(
                year => 2012, month => 5, day => 8, hour => 10, minute => 2, second => 14, time_zone => "+0000",
            ),
            text => 'Check out this <a href="http://external.site.com/hoge/page">page</a>.',
            entities => {
                hashtags => [],
                user_mentions => [],
                urls => [],
            },
            busybird => {
                original => {
                    id => 998223,
                    id_str => "998223",
                }
            }
        ]),
        expect_format => {
            json => q{
{
    "id": "RSS_http://some.site.com/feed?format=rss_998223",
    "id_str": "RSS_http://some.site.com/feed?format=rss_998223",
    "created_at": "Tue May 08 10:02:14 +0000 2012",
    "text": "Check out this <a href=\"http://external.site.com/hoge/page\">page</a>.",
    "entities": {
        "hashtags": [],
        "user_mentions": [],
        "urls": []
    },
    "busybird": {
        "original": {
            "id": 998223,
            "id_str": "998223"
        }
    }
}
},
            xml => q{<status>
<busybird>
  <original>
    <id>998223</id>
    <id_str>998223</id_str>
  </original>
</busybird>
<created_at>Tue May 08 10:02:14 +0000 2012</created_at>
<entities>
  <hashtags />
  <urls />
  <user_mentions />
</entities>
<id>RSS_http://some.site.com/feed?format=rss_998223</id>
<id_str>RSS_http://some.site.com/feed?format=rss_998223</id_str>
<text>Check out this &lt;a href="http://external.site.com/hoge/page"&gt;page&lt;/a&gt;.</text>
</status>},
        }
    }
);


foreach my $tester (\&testJSON, \&testXML, \&testSerialize) {
    foreach my $i (0 .. $#statuses_for_test) {
        note("Test status $i");
        $tester->(@statuses_for_test[($i)]);
    }
    note("Test status all");
    $tester->(@statuses_for_test);
    note("Test empty status");
    $tester->();
}

&testClone($_) foreach @statuses_for_test;


done_testing();


