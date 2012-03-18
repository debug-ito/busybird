#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('JSON');
    use_ok('DateTime');
    use_ok('BusyBird::Status');
}

sub singleTest {
    my ($datetime, $exp_created_at) = @_;
    isa_ok($datetime, 'DateTime');
    my $expected_output = {
        id => 'hoge',
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
    my $status = new_ok('BusyBird::Status');
    $status->setDateTime($datetime);
    $status->set(
        'id' => 'hoge',
        'text' => 'foo bar',
        'user/screen_name' => 'screenName',
        'user/name' => 'na me',
        'busybird/input_name' => 'input',
    );
    is($status->getDateTime(), $datetime);
    my $json_status = $status->getJSON();
    cmp_ok($json_status, 'ne', '');
    my $decoded_json = decode_json($json_status);
    is_deeply($decoded_json, $expected_output);
}

BusyBird::Status->setTimeZone('UTC');
&singleTest(DateTime->new(
    year   => 2011,
    month  => 6,
    day    => 14,
    hour   => 9,
    minute => 45,
    second => 11,
    time_zone => '+0000',
), 'Tue Jun 14 09:45:11 +0000 2011');

done_testing();


