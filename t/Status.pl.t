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

sub createTestStatus {
    my ($datetime) = @_;
    isa_ok($datetime, 'DateTime');
    my $status = new_ok('BusyBird::Status', [id => 'hoge', id_str => 'hoge', created_at => $datetime]);
    $status->content->{text} = 'foo bar';
    $status->content->{in_reply_to_screen_name} = undef;
    $status->content->{user}{screen_name} = 'screenName';
    $status->content->{user}{name} = 'na me';
    $status->content->{user}{profile_image_url} = undef;
    $status->content->{busybird}{input_name} = 'input';
    $status->content->{busybird}{score} = undef;
    is($status->content->{created_at}, $datetime);
    return $status;
}

sub testJSON {
    my ($datetime, $exp_created_at) = @_;
    note("--- testJSON");
    my $status = &createTestStatus($datetime);
    my $exp_statuses_json = qq{
[{
    "id": "hoge",
    "id_str": "hoge",
    "created_at": "$exp_created_at",
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
}]
};
    my $json_statuses = BusyBird::Status->format('json', [$status]);
    cmp_ok($json_statuses, 'ne', '');
    my $decoded_got_json = decode_json($json_statuses);
    my $decoded_exp_json = decode_json($exp_statuses_json);
    is_deeply($decoded_got_json, $decoded_exp_json);
}

sub testXML {
    my ($datetime, $exp_created_at) = @_;
    note("--- testXML");
    my $status = &createTestStatus($datetime);
    my $exp_xml = qq{
<statuses type="array">
<status>
  <id>hoge</id>
  <busybird>
    <input_name>input</input_name>
    <score />
  </busybird>
  <created_at>$exp_created_at</created_at>
  <id_str>hoge</id_str>
  <in_reply_to_screen_name />
  <text>foo bar</text>
  <user>
    <name>na me</name>
    <profile_image_url />
    <screen_name>screenName</screen_name>
  </user>
</status>
</statuses>
};
    my $got_xml = BusyBird::Status->format('xml', [$status]);
    xml_valid $got_xml, 'Valid XML document';
    xml_node $got_xml, '/statuses', 'XML node /statuses exists';
    xml_is_deeply $got_xml, '/statuses', $exp_xml, 'XML content is what is expected' or do {
        diag("GOT XML: $got_xml");
        fail('xml_is_deeply failed.');
    };
}

sub testClone {
    note("--- testClone");
    my $time = DateTime->now();
    my $orig = new_ok('BusyBird::Status', [id => '102023010', id_str => '102023010', created_at => $time]);
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

sub testSerialize {
    my ($statuses) = @_;
    note("--- testSerialize");
    my $serialized = BusyBird::Status->serialize($statuses);
    ok(defined($serialized), "serialize() returns a defined value");
    ok(!ref($serialized), "... and it's a scalar");
    my $des_statuses = BusyBird::Status->deserialize($serialized);
    ok(defined($des_statuses), "deserialize() returns defined value");
    is(ref($des_statuses), 'ARRAY', "... and it's an array ref.");
    is_deeply($des_statuses, $statuses, "statuses are restored perfectly.");
}

BusyBird::Status->setTimeZone('UTC');

foreach my $testpair (
    [DateTime->new(
        year   => 2011,
        month  => 6,
        day    => 14,
        hour   => 10,
        minute => 45,
        second => 11,
        time_zone => '+0900',
    ), 'Tue Jun 14 01:45:11 +0000 2011']
) {
    &testJSON(@$testpair);
    &testXML(@$testpair);
}


&testClone();


&testSerialize([
    BusyBird::Status->new(
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
    ),
    BusyBird::Status->new(
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
            }
        },
    ),
]);

done_testing();


