use strict;
use warnings;
use Test::More;
use BusyBird::Filter ":all";

{
    note("--- filter_each");
    my $input = [
        {id => 0, text => "hoge", user => { screen_name => "foobar" }},
        {id => 1, text => "huga", user => { screen_name => "buzz" }},
    ];
    my $called = 0;
    my $func = sub {
        my $status = shift;
        $called++;
        is wantarray, undef, "func is in void context";
        $status->{text} = "$status->{text}!?";
        $status->{user}{screen_name} =~ s/(.*)/uc($1)/e;
    };
    my $exp = [
        {id => 0, text => "hoge!?", user => { screen_name => "FOOBAR" }},
        {id => 1, text => "huga!?", user => { screen_name => "BUZZ" }},
    ];

    my $filter = filter_each $func;
    is_deeply $filter->($input), $exp, "filter_each result OK";
    is $called, 2, "filter func is called twice";
}

{
    note("--- filter_map");
    my $input = [
        {op => "echo"},
        {op => "drop"},
        {op => "nop"},
        {op => "modify", obj => { prop => "hoge" }},
    ];
    my $called = 0;
    my $func = sub {
        my $status = shift;
        $called++;
        ok wantarray, "func is in list context";
        if($status->{op} eq "echo") {
            return ($status, $status);
        }elsif($status->{op} eq "drop") {
            %{$status} = ();
            return ();
        }elsif($status->{op} eq "modify") {
            $status->{obj}{prop} =~ s/og/OG/;
            return $status;
        }else {
            return $status;
        }
    };
    my $exp = [
        {op => "echo"},
        {op => "echo"},
        {op => "nop"},
        {op => "modify", obj => { prop => "hOGe" }},
    ];

    my $filter = filter_map $func;
    is_deeply $filter->($input), $exp, "filter_map result OK";
    is $called, 4, "filter_map func is called four times";
    is_deeply $input, [
        {op => "echo"},
        {op => "drop"},
        {op => "nop"},
        {op => "modify", obj => { prop => "hoge" }},
    ], "input is left intact";
}

done_testing;

