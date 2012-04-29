#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('BusyBird::HTTPD::PathMatcher');
}

sub checkMatch {
    my ($matcher, $path, $expected_list, $message) = @_;
    my $got = [ $matcher->match($path) ];
    cmp_ok(int(@$got), '==', int(@$expected_list), int(@$expected_list) . " elements returned") or return fail($message);
    foreach (0 .. $#{$expected_list}) {
        if(defined($expected_list->[$_])) {
            is($got->[$_], $expected_list->[$_], "index $_ is expected to be $expected_list->[$_]") or return fail($message);
        }else {
            ok(!defined($got->[$_]), "index $_ is expected to be undef") or return fail($message);
        }
        
    }
    return pass($message);
}

{
    diag('------ match normal string');
    my $match_path = "/exactly/this/path.html";
    my $matcher = new_ok('BusyBird::HTTPD::PathMatcher', [$match_path]);
    isa_ok($matcher, 'BusyBird::HTTPD::PathMatcher::String');
    &checkMatch($matcher, $match_path, [$match_path], 'matched');
    &checkMatch($matcher, '/not' . $match_path, [], 'not matched to super-path...');
    &checkMatch($matcher, $match_path . '/hoge', [], 'nor sub-path...');
    &checkMatch($matcher, '', [], 'nor empty path');
    &checkMatch($matcher, undef, [], 'always no match for undef');
    is($matcher->toString, $match_path, "toString returns the match_path itself");
}

sub checkHashMatch{
    my ($matcher, $key, $path) = @_;
    &checkMatch($matcher, $path, [$path, $key], "match returns ($path, $key)");
}

{
    diag('------ match hash');
    my $match_obj = {
        finn => '/species/human',
        jake => '/species/dog',
        bubblegum => '/species/candy',
        marceline => '/species/vampire',
    };
    my $matcher = new_ok('BusyBird::HTTPD::PathMatcher', [$match_obj]);
    isa_ok($matcher, 'BusyBird::HTTPD::PathMatcher::Hash');
    foreach my $key (keys %$match_obj) {
        &checkHashMatch($matcher, $key, $match_obj->{$key});
    }
    &checkMatch($matcher, '/species/cloud', [], 'no match for cloud people');
    &checkMatch($matcher, '/world/species/human', [], 'not matched to super-path...');
    &checkMatch($matcher, '/species/candy/royal', [], 'nor sub-path');
    &checkMatch($matcher, '', [], 'empty path');
    &checkMatch($matcher, undef, [], 'undef');
    my $s = $matcher->toString;
    ok(($s =~ /human/ and $s =~ /dog/ and $s =~ /candy/ and $s =~ /vampire/), 'toString contains all the paths');
}

{
    diag('------ match array');
    my $match_obj = ['/count/zero', '/count/one', '/count/two'];
    my $matcher = new_ok('BusyBird::HTTPD::PathMatcher', [$match_obj]);
    isa_ok($matcher, 'BusyBird::HTTPD::PathMatcher::Hash');
    foreach my $key (0 .. $#{$match_obj}) {
        &checkHashMatch($matcher, $key, $match_obj->[$key]);
    }
}

{
    diag('------ match regexp');
    my $matcher = new_ok('BusyBird::HTTPD::PathMatcher', [qr!/(this|that)/dir/list(\.([^/]+))?$!]);
    isa_ok($matcher, 'BusyBird::HTTPD::PathMatcher::Regexp');
    &checkMatch($matcher, '/this/dir/list.json', [qw(/this/dir/list.json this .json json)], 'matched and extract path elems');
    &checkMatch($matcher, '/super/path/that/dir/list.tar.gz',
                [qw(/super/path/that/dir/list.tar.gz that .tar.gz tar.gz)], 'matched to super-path');
    &checkMatch($matcher, '/this/dir/list.json/id/3', [], 'not matched to sub-path in this case');
    &checkMatch($matcher, '/what/dir/list.json', [], 'not matched to dir "what"');
    &checkMatch($matcher, '/v1/that/dir/list', ['/v1/that/dir/list', 'that', undef, undef], 'matched without extension');
    &checkMatch($matcher, '/foo/this/dir/list.', [], 'not matched if the path has period at the end but no extension');
}

done_testing();






