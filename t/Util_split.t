use strict;
use warnings;
use Test::More;
use Test::Exception;
use utf8;

BEGIN {
    use_ok('BusyBird::Util', 'split_with_entities');
}

{
    note("--- for example");
    my $text = 'aaa --- bb ---- ccaa -- ccccc';
    my $entities = {
        a => [
            {indices => [0, 3],   url => 'http://hoge.com/a/1'},
            {indices => [18, 20], url => 'http://hoge.com/a/2'},
        ],
        b => [
            {indices => [8, 10], style => "bold"},
        ],
        c => [
            {indices => [16, 18], footnote => 'first c'},
            {indices => [24, 29], some => {complex => 'structure'}},
        ],
        d => []
    };
    my $exp_segments = [
        { text => 'aaa', start => 0, end => 3, type => 'a',
          entity => {indices => [0, 3], url => 'http://hoge.com/a/1'} },
        { text => ' --- ', start => 3, end => 8, type => undef,
          entity => undef},
        { text => 'bb', start => 8, end => 10, type => 'b',
          entity => {indices => [8, 10], style => "bold"} },
        { text => ' ---- ', start => 10, end =>  16, type => undef,
          entity => undef },
        { text => 'cc', start => 16, end => 18, type => 'c',
          entity => {indices => [16, 18], footnote => 'first c'} },
        { text => 'aa', start => 18, end => 20, type => 'a',
          entity => {indices => [18, 20], url => 'http://hoge.com/a/2'} },
        { text => ' -- ', start => 20, end => 24, type => undef,
          entity => undef },
        { text => 'ccccc', start => 24, end => 29, type => 'c',
          entity => {indices => [24, 29], some => {complex => 'structure'}} }
    ];
    my $got_segments = split_with_entities($text, $entities);
    is_deeply($got_segments, $exp_segments, "example split OK") or diag(explain $got_segments);
}

{
    note("--- other cases");
    foreach my $case (
        {label => "utf8 text", text => 'これはＵＴＦー８テキスト',
         entities => { alphanum => [{indices => [3, 8], alpha => 1, num => 1}] },
         exp_segments => [
             {text => 'これは', start => 0, end => 3, type => undef, entity => undef},
             {text => 'ＵＴＦー８', start => 3, end => 8, type => 'alphanum', entity => {
                 indices => [3, 8], alpha => 1, num => 1
             }},
             {text => 'テキスト', start => 8, end => 12, type => undef, entity => undef},
         ]},
        
        {label => '0-length entity', text => 'aaaBBBccc',
         entities => {
             boundary => [
                 {indices => [0,0], desc => 'before a'},
                 {indices => [3,3], desc => 'before B'},
                 {indices => [3,3], desc => 'before B 2'},
                 {indices => [6,6], desc => 'before c'},
                 {indices => [9,9], desc => 'tail'},
             ]
         },
         exp_segments => [
             {text => '', start => 0, end => 0, type => 'boundary', entity => {
                 indices => [0,0], desc => 'before a'
             }},
             {text => 'aaa', start => 0, end => 3, type => undef, entity => undef},
             {text => '', start => 3, end => 3, type => 'boundary', entity => {
                 indices => [3,3], desc => 'before B'
             }},
             {text => '', start => 3, end => 3, type => 'boundary', entity => {
                 indices => [3,3], desc => 'before B 2'
             }},
             {text => 'BBB', start => 3, end => 6, type => undef, entity => undef},
             {text => '', start => 6, end => 6, type => 'boundary', entity => {
                 indices => [6,6], desc => 'before c'
             }},
             {text => 'ccc', start => 6, end => 9, type => undef, entity => undef},
             {text => '', start => 9, end => 9, type => 'boundary', entity => {
                 indices => [9,9], desc => 'tail'
             }},
         ]},
        {label => "no entities", text => "hoge hoge hoge",
         entities => {},
         exp_segments => [
             {text => "hoge hoge hoge", start => 0, end => 14, type => undef, entity => undef},
         ]},
        {label => "undef entities", text => "foobar",
         entities => undef,
         exp_segments => [
             {text => "foobar", start => 0, end => 6, type => undef, entity => undef}
         ]},
    ) {
        my $got_segments = split_with_entities($case->{text}, $case->{entities});
        is_deeply($got_segments, $case->{exp_segments}, "$case->{label}: OK") or diag(explain $got_segments);
    }
}

{
    note("--- undef text");
    dies_ok {
        split_with_entities(undef, {});
    } 'it should die if $text is undef';
}

done_testing();


