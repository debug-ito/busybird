#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('DateTime');
    use_ok('BusyBird::Status');
    use_ok('BusyBird::Output');
}

sub checkStatusNum {
    my ($output, $expected_new_num, $expected_old_num) = @_;
    my $new_entries = $output->_getNewStatuses();
    my $old_entries = $output->_getOldStatuses();
    cmp_ok(int(@$new_entries), '==', $expected_new_num, sprintf("number of new_statuses in %s", $output->getName));
    cmp_ok(int(@$old_entries), '==', $expected_old_num, sprintf("number of old_statuses in %s", $output->getName));
    ok($_->content->{busybird}{is_new}, "this status is new") foreach @$new_entries;
    ok(!$_->content->{busybird}{is_new}, "this status is old") foreach @$old_entries;
}

sub checkPagination {
    my ($output, $detail, @expected_ids) = @_;
    my $got_statuses = $output->_getPagedStatuses(%$detail);
    ## my ($result_code, $result_ref, $mime) = $output->_replyAllStatuses($detail);
    my $detail_str = "";
    while(my ($key, $val) = each(%$detail)) {
        $detail_str .= "$key => $val, ";
    }
    diag(sprintf("checkPagination: output: %s, %s", $output->getName(), $detail_str));
    ## is(ref($result), 'ARRAY', 'AllStatuses result is an array ref...');
    ## cmp_ok(int(@$result), ">=", 3, "and it has at least 3 elements.");
    ## my %headers = ( @{$result->[1]} );
    ## ok(defined($headers{'Content-Type'}), 'Content-Type header exists...');
    ## like($headers{'Content-Type'}, qr(application/json), "and it's JSON.");
    ## my $got_statuses = JSON::decode_json($result->[2]->[0]);
    is(ref($got_statuses), 'ARRAY', "returned an array-ref");
    cmp_ok(int(@$got_statuses), "==", int(@expected_ids), "number of statuses is what is expected.");
    foreach my $i (0 .. $#expected_ids) {
        is($got_statuses->[$i]->content->{id}, $expected_ids[$i], "ID is " . $expected_ids[$i]);
    }
}

my $next_id = 1;

sub generateStatus {
    my ($id) = @_;
    
    if(!defined($id)) {
        $id = $next_id;
        $next_id++;
    }elsif($id >= $next_id) {
        $next_id = $id + 1;
    }
    my $status = new_ok('BusyBird::Status', [
        id => $id,
        created_at => DateTime->from_epoch(epoch => $id)
    ]);
    return $status;
}

sub main {
    my $output;
    eval {
        $output = BusyBird::Output->new();
        fail("Output should not be created without a name.");
    }; if($@) {
        pass("Output should not be created without a name.");
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

    diag('------ _confirm() should make new statuses old.');
    $output->_confirm();
    &checkStatusNum($output, 0, 10);
    $output->pushStatuses([&generateStatus()]) foreach (1..5);
    &checkStatusNum($output, 5, 10);
    $output->pushStatuses([&generateStatus($_)]) foreach (1..5);
    &checkStatusNum($output, 5, 10);

    diag('------ _getPagedStatuses() pagination test.');
    $output->pushStatuses([&generateStatus()]) foreach (1..55);
    $output->_confirm();
    $output->pushStatuses([&generateStatus()]) foreach (1..65);
    &checkStatusNum($output, 65, 70);
    
    diag('------ --- Without per_page option, page 1 always includes all of the new statuses. Old statuses are separated by the default per_page value.');
    &checkPagination($output, {}, reverse(51 .. 135));
    &checkPagination($output, {page => 0}, reverse(51 .. 135));
    &checkPagination($output, {page => 1}, reverse(51 .. 135));
    &checkPagination($output, {page => 2}, reverse(31 .. 50));
    &checkPagination($output, {page => 3}, reverse(11 .. 30));
    &checkPagination($output, {page => 4}, reverse(1  .. 10));
    &checkPagination($output, {page => 5}, ());
    &checkPagination($output, {max_id => 100, page => 1}, reverse(51 .. 100));
    &checkPagination($output, {max_id => 100, page => 2}, reverse(31 .. 50));
    &checkPagination($output, {max_id => 100, page => 3}, reverse(11 .. 30));
    &checkPagination($output, {max_id => 100, page => 4}, reverse(1  .. 10));
    &checkPagination($output, {max_id => 100, page => 5}, ());
    &checkPagination($output, {max_id => 60,  page => 1}, reverse(41 .. 60));
    &checkPagination($output, {max_id => 60,  page => 2}, reverse(21 .. 40));
    &checkPagination($output, {max_id => 60,  page => 3}, reverse(1 .. 20));
    &checkPagination($output, {max_id => 60,  page => 4}, ());

    diag('------ --- With per_page option, new and old statuses are treated as a single status line.');
    &checkPagination($output, {per_page => 30, page => 0}, reverse(106 .. 135));
    &checkPagination($output, {per_page => 30, page => 1}, reverse(106 .. 135));
    &checkPagination($output, {per_page => 30, page => 2}, reverse(76 .. 105));
    &checkPagination($output, {per_page => 30, page => 3}, reverse(46 .. 75));
    &checkPagination($output, {per_page => 30, page => 4}, reverse(16 .. 45));
    &checkPagination($output, {per_page => 30, page => 5}, reverse(1  .. 15));
    &checkPagination($output, {per_page => 30, page => 6}, ());
    &checkPagination($output, {per_page => 100, page => 1}, reverse(36 .. 135));
    &checkPagination($output, {per_page => 100, page => 2}, reverse(1 .. 35));
    &checkPagination($output, {per_page => 100, page => 3}, ());
    &checkPagination($output, {per_page => 500, page => 1}, reverse(1 .. 135));
    &checkPagination($output, {per_page => 500, page => 2}, ());
    &checkPagination($output, {max_id => 125, per_page => 40, page => 1}, reverse(86 .. 125));
    &checkPagination($output, {max_id => 125, per_page => 40, page => 2}, reverse(46 .. 85));
    &checkPagination($output, {max_id => 125, per_page => 40, page => 3}, reverse(6  .. 45));
    &checkPagination($output, {max_id => 125, per_page => 40, page => 4}, reverse(1  .. 5));
    &checkPagination($output, {max_id => 125, per_page => 40, page => 5}, ());
    &checkPagination($output, {max_id => 60, per_page => 40, page => 1}, reverse(21 .. 60));
    &checkPagination($output, {max_id => 60, per_page => 40, page => 2}, reverse(1  .. 20));
    &checkPagination($output, {max_id => 60, per_page => 40, page => 3}, ());

    diag('------ --- With invalid max_id option, pagination should start from index 0');
    &checkPagination($output, {max_id => 'this_does_not_exist', page => 1}, reverse(51 .. 135));
    &checkPagination($output, {max_id => 'this_does_not_exist', page => 2}, reverse(31 .. 50));
    
    done_testing();
}

&main();

