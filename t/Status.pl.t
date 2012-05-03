#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('JSON');
    use_ok('DateTime');
    use_ok('BusyBird::Status');
}

sub testJSON {
    my ($datetime, $exp_created_at) = @_;
    diag("testJSON");
    isa_ok($datetime, 'DateTime');
    my $expected_output = {
        id => 'hoge',
        id_str => 'hoge',
        created_at => $exp_created_at,
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
        },
    };
    my $status = new_ok('BusyBird::Status', [id => 'hoge', created_at => $datetime]);
    $status->content->{text} = 'foo bar';
    $status->content->{in_reply_to_screen_name} = undef;
    $status->content->{user}{screen_name} = 'screenName';
    $status->content->{user}{name} = 'na me';
    $status->content->{user}{profile_image_url} = undef;
    $status->content->{busybird}{input_name} = 'input';
    $status->content->{busybird}{score} = undef;
    is($status->content->{created_at}, $datetime);
    my $json_status = $status->format_json();
    cmp_ok($json_status, 'ne', '');
    my $decoded_json = decode_json($json_status);
    is_deeply($decoded_json, $expected_output);
}

sub testClone {
    diag("testClone");
    my $time = DateTime->now();
    my $orig = new_ok('BusyBird::Status', [id => '102023010', created_at => $time]);
    $orig->put(
        text => 'hoge hoge hoge',
        user => {
            screen_name => 'some_user',
            name => 'Some User',
        },
        busybird => {
            input_name => 'Input',
            score => 100,
        }
    );
    my $clone = $orig->clone();
    $clone->content->{busybird}{score} = 40;
    cmp_ok($orig ->content->{busybird}{score}, '==', 100, 'original score');
    cmp_ok($clone->content->{busybird}{score}, '==',  40, 'cloned score');
    cmp_ok(DateTime->compare($orig->content->{created_at}, $clone->content->{created_at}), '==', 0, 'time is the same');
    delete $orig ->content->{busybird}{score};
    delete $clone->content->{busybird}{score};
    is_deeply($orig->content, $clone->content, "everything except score is the same");
}

BusyBird::Status->setTimeZone('UTC');

&testJSON(DateTime->new(
    year   => 2011,
    month  => 6,
    day    => 14,
    hour   => 9,
    minute => 45,
    second => 11,
    time_zone => '+0000',
), 'Tue Jun 14 09:45:11 +0000 2011');

&testClone();

done_testing();


