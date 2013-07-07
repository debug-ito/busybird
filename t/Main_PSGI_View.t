use strict;
use warnings;
use Test::More;
use Test::Builder;
use BusyBird::Main;
use BusyBird::Log;
use BusyBird::StatusStorage::SQLite;
use JSON qw(decode_json);
use utf8;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use BusyBird::Test::HTTP;

BEGIN {
    use_ok("BusyBird::Main::PSGI::View");
}

$BusyBird::Log::Logger = undef;

sub test_psgi_response {
    my ($psgi_res, $exp_code, $label) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is(ref($psgi_res), "ARRAY", "$label: top array-ref OK");
    is($psgi_res->[0], $exp_code, "$label: status code OK");
    is(ref($psgi_res->[1]), "ARRAY", "$label: header array-ref OK");
    is(ref($psgi_res->[2]), "ARRAY", "$label: content array-ref OK");
}

sub test_json_response {
    my ($psgi_res, $exp_code, $exp_obj, $label) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    test_psgi_response($psgi_res, $exp_code, $label);
    my $got_obj = decode_json(join("", @{$psgi_res->[2]}));
    is_deeply($got_obj, $exp_obj, "$label: json object OK");
}

sub create_main {
    my $main = BusyBird::Main->new;
    $main->set_config(
        default_status_storage => BusyBird::StatusStorage::SQLite->new(path => ':memory:')
    );
    $main->timeline('test');
    return $main;
}

{
    note("--- response methods");
    my $main = create_main();
    my $view = new_ok("BusyBird::Main::PSGI::View", [main_obj => $main]);

    test_psgi_response($view->response_notfound(), 404, "notfound");
    
    test_json_response($view->response_json(200, {}),
                       200, {error => undef}, "json, 200, empty hash");
    test_json_response($view->response_json(200, [0,1,2]),
                       200, [0,1,2], "json, 200, array");
    test_json_response($view->response_json(400, {}),
                       400, {}, "json, 400, empty hash");
    test_json_response($view->response_json(500, {error => "something bad happened"}),
                       500, {error => "something bad happened"}, "json, 500, error set");
    test_json_response($view->response_json(200, {main => $main}),
                       500, {error => "error while encoding to JSON."}, "json, 500, unable to encode");

    test_psgi_response($view->response_statuses(statuses => [], http_code => 200, format => "html", timeline_name => "test"),
                       200, "statuses success");
    test_psgi_response($view->response_statuses(error => "hoge", http_code => 400, format => "html", timeline_name => "test"),
                       400, "statuses failure");
    test_psgi_response($view->response_statuses(statuses => [], http_code => 200, format => "foobar", timeline_name => "test"),
                       400, "statuses unknown format");

    test_psgi_response($view->response_timeline("test", ""), 200, "existent timeline");
    test_psgi_response($view->response_timeline("hoge", ""), 404, "missing timeline");
}

{
    note("--- template_functions");
    my $main = create_main();
    my $view = BusyBird::Main::PSGI::View->new(main_obj => $main);
    my $funcs = $view->template_functions();

    note("--- -- js"); ## from SYNOPSIS of JavaScript::Value::Escape with a small modification
    is($funcs->{js}->(q{&foo"bar'</script>}), "\\u0026foo\\u0022bar\\u0027\\u003c/script\\u003e", "js filter OK");

    note("--- -- link");
    foreach my $case (
        {label => "escape text", args => ['<hoge>', href => 'http://example.com/'],
         exp => '<a href="http://example.com/">&lt;hoge&gt;</a>'},
        {label => "external href", args => ['foo & bar', href => 'https://www.google.co.jp/search?channel=fs&q=%E3%81%BB%E3%81%92&ie=utf-8&hl=ja#112'],
         exp => '<a href="https://www.google.co.jp/search?channel=fs&q=%E3%81%BB%E3%81%92&ie=utf-8&hl=ja#112">foo &amp; bar</a>'},
        {label => "internal absolute href",
         args => ['hoge', href => '/timelines/hoge/statuses.html?count=10&max_id=http%3A%2F%2Fhoge.com%2F%3Fid%3D31245%26cat%3Dfoo'],
         exp => '<a href="/timelines/hoge/statuses.html?count=10&max_id=http%3A%2F%2Fhoge.com%2F%3Fid%3D31245%26cat%3Dfoo">hoge</a>'},
        {label => "with target and class", args => ['ほげ', href => '/', target => '_blank', class => 'link important'],
         exp => '<a href="/" target="_blank" class="link important">ほげ</a>'},
        {label => "no href", args => ['no link', class => "hogeclass"],
         exp => 'no link'},
        {label => "javascript: href", args => ['alert!', href => 'javascript: alert("hogehoge"); return false;'],
         exp => 'alert!'},
        {label => "empty text", args => ['', href => 'http://empty.net/'],
         exp => '<a href="http://empty.net/"></a>'},
        {label => "undef text", args => [undef], exp => ""},
    ) {
        is($funcs->{link}->(@{$case->{args}}), $case->{exp}, "$case->{label} OK");
    }

    note("--- -- image");
    foreach my $case (
        {label => "external http", args => [src => "http://www.hoge.com/images.php?id=101&size=large"],
         exp => '<img src="http://www.hoge.com/images.php?id=101&size=large" />'},
        {label => "external https", args => [src => "https://example.co.jp/favicon.ico"],
         exp => '<img src="https://example.co.jp/favicon.ico" />'},
        {label => "internal absolute", args => [src => "/static/hoge.png"],
         exp => '<img src="/static/hoge.png" />'},
        {label => "with width, height and class",
         args => [src => '/foobar.jpg', width => "400", height => "300", class => "foo bar"],
         exp => '<img src="/foobar.jpg" width="400" height="300" class="foo bar" />'},
        {label => "no src", args => [], exp => ''},
        {label => "script", args => [src => '<script>alert("hoge");</script>'],
         exp => ''},
        {label => "data:",
         args => [src => 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAAAXNSR0IArs4c6QAAAAxJREFUCNdjuKCgAAAC1AERHXzACQAAAABJRU5ErkJggg=='],
         exp => ''},
        {label => "javascript:", args => [src => 'javascript: alert("hoge");'],
         exp => ''},
    ) {
        is($funcs->{image}->(@{$case->{args}}), $case->{exp}, "$case->{label} OK");
    }

    note("--- -- bb_level");
    foreach my $case (
        {label => "positive level", args => [10], exp => "10"},
        {label => "zero", args => [0], exp => "0"},
        {label => "negative level", args => [-5], exp => "-5"},
        {label => "undef", args => [undef], exp => "0"},
    ) {
        is($funcs->{bb_level}->(@{$case->{args}}), $case->{exp}, "$case->{label} OK");
    }
}

{
    note("--- template_functions_for_timeline");
    my $main = create_main();
    my $view = BusyBird::Main::PSGI::View->new(main_obj => $main);
    my $funcs = $view->template_functions_for_timeline('test');
    $main->set_config(
        time_zone => "UTC",
        time_format => '%Y-%m-%d %H:%M:%S',
        time_locale => 'en_US',
    );

    note("--- -- bb_timestamp");
    foreach my $case (
        {label => 'normal', args => ['Tue May 28 20:10:13 +0900 2013'], exp => '2013-05-28 11:10:13'},
        {label => 'undef', args => [undef], exp => ''},
        {label => 'empty string', args => [''], exp => ''},
    ) {
        is($funcs->{bb_timestamp}->(@{$case->{args}}), $case->{exp}, "$case->{label}: OK");
    }

    note("--- -- bb_status_permalink");
    foreach my $case (
        {label => "complete status",
         args => [{id => "191", user => {screen_name => "hoge"}, busybird => {status_permalink => "http://hoge.com/"}}],
         exp => "http://hoge.com/"},
        {label => "missing status_permalink field",
         args => [{id => "191", user => {screen_name => "hoge"}}],
         exp => "https://twitter.com/hoge/status/191"},
        {label => "unable to build", args => [{id => "191"}], exp => ""},
        {label => "invalid status_permalink",
         args => [{id => "191", busybird => {status_permalink => "javascript: alert('hoge')"}}],
         exp => ""},
    ) {
        is($funcs->{bb_status_permalink}->(@{$case->{args}}), $case->{exp}, "$case->{label}: OK");
    }

    note("--- -- bb_text");
    foreach my $case (
        {label => "HTML special char, no URL, no entity",
         args => [{text => q{foo bar "A & B"} }],
         exp => q{foo bar &quot;A &amp; B&quot;}},
        
        {label => "URL and HTML special char, no entity",
         args => [{id => "hoge", text => 'this contains URL http://hogehoge.com/?a=foo+bar&b=%2Fhoge here :->'}],
         exp => q{this contains URL <a href="http://hogehoge.com/?a=foo+bar&b=%2Fhoge">http://hogehoge.com/?a=foo+bar&amp;b=%2Fhoge</a> here :-&gt;}},
        
        {label => "URL at the top and bottom",
         args => [{text => q{http://hoge.com/toc.html#item5 hogehoge http://foobar.co.jp/q=hoge&page=5}}],
         exp => q{<a href="http://hoge.com/toc.html#item5">http://hoge.com/toc.html#item5</a> hogehoge <a href="http://foobar.co.jp/q=hoge&page=5">http://foobar.co.jp/q=hoge&amp;page=5</a>}},
        
        {label => "Twitter Entities",
         args => [{
             text => q{てすと &lt;"&amp;hearts;&amp;&amp;hearts;"&gt; http://t.co/dNlPhACDcS &gt;"&lt; @debug_ito &amp; &amp; &amp; #test},
             entities => {
                 hashtags => [ { text => "test", indices => [106,111] } ],
                 user_mentions => [ {
                     "name" => "Toshio Ito",
                     "id" => 797588971,
                     "id_str" => "797588971",
                     "indices" => [ 77, 87 ],
                     "screen_name" => "debug_ito"
                 } ],
                 symbols => [],
                 urls => [ {
                     "display_url" => "google.co.jp",
                     "expanded_url" => "http://www.google.co.jp/",
                     "url" => "http://t.co/dNlPhACDcS",
                     "indices" => [ 44, 66 ]
                 } ]
             }
         }],
         exp => q{てすと &amp;lt;&quot;&amp;amp;hearts;&amp;amp;&amp;amp;hearts;&quot;&amp;gt; <a href="http://t.co/dNlPhACDcS">google.co.jp</a> &amp;gt;&quot;&amp;lt; <a href="https://twitter.com/debug_ito">@debug_ito</a> &amp;amp; &amp;amp; &amp;amp; <a href="https://twitter.com/search?q=%23test&src=hash">#test</a>}},

        {label => "2 urls entities",
         args => [{
             text => q{http://t.co/0u6Ki0bOYQ - plain,  http://t.co/0u6Ki0bOYQ - with scheme},
             entities => {
                 "hashtags" => [],
                 "user_mentions" => [],
                 "symbols" => [],
                 "urls" => [
                     {
                         "display_url" => "office.com",
                         "expanded_url" => "http://office.com",
                         "url" => "http://t.co/0u6Ki0bOYQ",
                         "indices" => [ 0, 22 ]
                     },
                     {
                         "display_url" => "office.com",
                         "expanded_url" => "http://office.com",
                         "url" => "http://t.co/0u6Ki0bOYQ",
                         "indices" => [ 33, 55 ]
                     }
                 ]
             }
         }],
         exp => q{<a href="http://t.co/0u6Ki0bOYQ">office.com</a> - plain,  <a href="http://t.co/0u6Ki0bOYQ">office.com</a> - with scheme}},

        {label => "Unicode hashtags and media entities",
         args => [{
             text => q{ドコモ「docomo Wi-Fi」、南海/阪急/JR 九州でサービス エリア拡大 http://t.co/mvgqG5v3mQ #南海 #阪急 #JR九州 http://t.co/U3h7lEDZKT},
             entities => {
                 "hashtags" => [
                     { "text" => "南海", "indices" => [64, 67] },
                     { "text" => "阪急", "indices" => [68, 71] },
                     { "text" => "JR九州", "indices" => [72, 77] }
                 ],
                 "user_mentions" => [],
                 "media" => [
                     {
                         "display_url" => "pic.twitter.com/U3h7lEDZKT",
                         "id_str" => "340966457888370689",
                         "sizes" => {
                             "small" => { "w" => 340, "resize" => "fit", "h" => 83 },
                             "large" => { "w" => 389, "resize" => "fit", "h" => 95 },
                             "medium" => { "w" => 389, "resize" => "fit", "h" => 95 },
                             "thumb" => { "w" => 150, "resize" => "crop", "h" => 95 }
                         },
                         "expanded_url" => "http://twitter.com/jic_news/status/340966457884176384/photo/1",
                         "media_url_https" => "https://pbs.twimg.com/media/BLtbL9rCcAEfjCr.jpg",
                         "url" => "http://t.co/U3h7lEDZKT",
                         "indices" => [78,100],
                         "type" => "photo",
                         "id" => 340966457888370689,
                         "media_url" => "http://pbs.twimg.com/media/BLtbL9rCcAEfjCr.jpg"
                     }
                 ],
                 "symbols" => [],
                 "urls" => [
                     {
                         "display_url" => "bit.ly/14jappE",
                         "expanded_url" => "http://bit.ly/14jappE",
                         "url" => "http://t.co/mvgqG5v3mQ",
                         "indices" => [41,63]
                     }
                 ]
             }
         }],
         exp => q{ドコモ「docomo Wi-Fi」、南海/阪急/JR 九州でサービス エリア拡大 <a href="http://t.co/mvgqG5v3mQ">bit.ly/14jappE</a> <a href="https://twitter.com/search?q=%23%E5%8D%97%E6%B5%B7&src=hash">#南海</a> <a href="https://twitter.com/search?q=%23%E9%98%AA%E6%80%A5&src=hash">#阪急</a> <a href="https://twitter.com/search?q=%23JR%E4%B9%9D%E5%B7%9E&src=hash">#JR九州</a> <a href="http://t.co/U3h7lEDZKT">pic.twitter.com/U3h7lEDZKT</a>}}
    ) {
        is($funcs->{bb_text}->(@{$case->{args}}), $case->{exp}, "$case->{label}: OK");
    }
}

{
    note("--- tests for response_timeline_list");
    my $main = create_main();
    my $view = BusyBird::Main::PSGI::View->new(main_obj => $main);
    foreach my $case (
        {
            label => "single page",
            input => {total_page_num => 1, cur_page => 0, timeline_unacked_counts => [
                {name => 'home', counts => {total => 5, 0 => 5}}
            ]},
            exp_timelines => [
                {link => "/timelines/home/", name => "home"}
            ]
        },
    ) {
        note("--- -- case: $case->{label}");
        my $exp_pager_num = ($case->{input}{total_page_num} > 1 ? 2 : 0);
        my $psgi_response = $view->response_timeline_list(%{$case->{input}}, script_name => "");
        test_psgi_response($psgi_response, 200, "PSGI response OK");
        my $tree = BusyBird::Test::HTTP->parse_html(join "", @{$psgi_response->[2]});
        my @pager_nodes = $tree->findnodes('//ul[@class="bb-timeline-page-list"]');
        is(scalar(@pager_nodes), $exp_pager_num, "$exp_pager_num pager objects should exist");
        my ($timeline_list_table) = $tree->findnodes('//table[@id="bb-timeline-list"]');
        isnt($timeline_list_table, undef, "timeline list table exists");
        my @timeline_rows = $timeline_list_table->findnodes('.//tr');
        my $exp_timeline_num = @{$case->{exp_timelines}};
        is(scalar(@timeline_rows), $exp_timeline_num, "$exp_timeline_num timeline rows.");
        foreach my $i (0 .. ($exp_timeline_num - 1)) {
            my $row = $timeline_rows[$i];
            my $exp_timeline = $case->{exp_timelines}[$i];
            my $href = $row->findvalue('.//a/@href');
            is($href, $exp_timeline->{link}, "link should be $exp_timeline->{link}");
            my ($name_node) = $row->findnodes('.//span[@class="bb-timeline-name"]');
            my $got_name = join "", $name_node->content_list;
            is($got_name, $exp_timeline->{name}, "name should be $exp_timeline->{name}");
        }
    }
}

done_testing();

