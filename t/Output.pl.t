#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('JSON');
    use_ok('BusyBird::Status');
    use_ok('BusyBird::Output');
}

my $next_id = 1;

sub generateStatus {
    my ($id) = @_;
    my $status = new_ok('BusyBird::Status');
    if(!defined($id)) {
        $id = $next_id;
        $next_id++;
    }elsif($id >= $next_id) {
        $next_id = $id + 1;
    }
    $status->set(id => $id);
    $status->setDateTime();
    return $status;
}

sub checkStatusNum {
    my ($output, $expected_new_num, $expected_old_num) = @_;
    diag("Status num for " . $output->getName);
    my $new_entries = $output->_getNewStatusesJSONEntries();
    my $old_entries = $output->_getOldStatusesJSONEntries();
    cmp_ok(int(@$new_entries), '==', $expected_new_num);
    cmp_ok(int(@$old_entries), '==', $expected_old_num);
}

sub checkPagination {
    my ($output, $detail, @expected_ids) = @_;
    my ($result_code, $result_ref, $mime) = $output->_replyAllStatuses($detail);
    my $detail_str = "";
    while(my ($key, $val) = each(%$detail)) {
        $detail_str .= "$key => $val, ";
    }
    diag("checkPagination: $detail_str");
    like($mime, qr(application/json));
    my $result = decode_json($$result_ref);
    is(ref($result), 'ARRAY');
    cmp_ok(int(@$result), "==", int(@expected_ids));
    foreach my $i (0 .. $#expected_ids) {
        is($result->[$i]->{id}, $expected_ids[$i]);
    }
}

sub main {
    my $output;
    eval {
        $output = BusyBird::Output->new();
        fail("Output should not be created without a name.");
    }; if($@) {
        pass();
    }

    $output = new_ok('BusyBird::Output', [name => "sample"]);
    is($output->getName, "sample");

    diag('------ pushStatuses() should take new statuses.');
    $output->pushStatuses([&generateStatus()]) foreach (1..5);
    &checkStatusNum($output, 5, 0);
    my @newones = ();
    push(@newones, &generateStatus()) foreach (1..5);
    $output->pushStatuses(\@newones);
    &checkStatusNum($output, 10, 0);

    diag('------ pushStatuses() should uniqify the input.');
    $output->pushStatuses([&generateStatus($_)]) foreach (1..5);
    &checkStatusNum($output, 10, 0);


    diag('------ _replyConfirm() should make new statuses old.');
    $output->_replyConfirm();
    &checkStatusNum($output, 0, 10);
    $output->pushStatuses([&generateStatus()]) foreach (1..5);
    &checkStatusNum($output, 5, 10);
    $output->pushStatuses([&generateStatus($_)]) foreach (1..5);
    &checkStatusNum($output, 5, 10);

    diag('------ _replyAllStatuses() pagination test.');
    $output->pushStatuses([&generateStatus()]) foreach (1..55);
    $output->_replyConfirm();
    $output->pushStatuses([&generateStatus()]) foreach (1..65);
    &checkStatusNum($output, 65, 70);
    &checkPagination($output, {}, reverse(51 .. 135));
    &checkPagination($output, {page => 0}, reverse(51 .. 135));
    &checkPagination($output, {page => 1}, reverse(51 .. 135));
    &checkPagination($output, {page => 2}, reverse(31 .. 50));
    &checkPagination($output, {page => 3}, reverse(11 .. 30));
    &checkPagination($output, {page => 4}, reverse(1  .. 10));
    &checkPagination($output, {page => 5}, ());
    &checkPagination($output, {per_page => 30, page => 0}, reverse(106 .. 135));
    &checkPagination($output, {per_page => 30, page => 1}, reverse(106 .. 135));
    &checkPagination($output, {per_page => 30, page => 2}, reverse(76 .. 105));
    &checkPagination($output, {per_page => 30, page => 3}, reverse(46 .. 75));
    
    done_testing();
}

&main();

