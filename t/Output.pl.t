#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('JSON');
    use_ok('DateTime');
    use_ok('BusyBird::Status');
    use_ok('BusyBird::Output');
}


package BusyBird::Test::Output::Request;
use strict;
use warnings;

sub new {
    my ($class, $hash_obj) = @_;
    if(!defined($hash_obj)) {
        $hash_obj = {};
    }
    return bless $hash_obj, $class;
}

sub parameters {
    my ($self) = @_;
    return $self;
}


package BusyBird::Test::Output;
use strict;
use warnings;
use Test::More;

sub new {
    my ($class, $output) = @_;
    my $self = bless {
        output => $output,
        reply_handlers => {},
    }, $class;
    foreach my $point qw(NewStatuses Confirm MainPage AllStatuses) {
        my $method = '_requestPoint' . $point;
        my ($name, $handler) = $output->$method();
        $self->{reply_handlers}->{$point} = $handler;
    }
    return $self;
}

sub raw {
    my $self = shift;
    return $self->{output};
}

sub request {
    my ($self, $point, $detail) = @_;
    if(!defined($self->{reply_handlers})) {
        die "Request point $point is not defined";
    }
    my $req = BusyBird::Test::Output::Request->new($detail);
    return $self->{reply_handlers}->{$point}->($req);
}

sub checkStatusNum {
    my ($self, $expected_new_num, $expected_old_num) = @_;
    my $output = $self->{output};
    my $new_entries = $output->_getNewStatusesJSONEntries();
    my $old_entries = $output->_getOldStatusesJSONEntries();
    cmp_ok(int(@$new_entries), '==', $expected_new_num, sprintf("number of new_statuses in %s", $output->getName));
    cmp_ok(int(@$old_entries), '==', $expected_old_num, sprintf("number of old_statuses in %s", $output->getName));
    ## ** it should check is_new flags here, but we need non-JSON interface first.
}

sub checkPagination {
    my ($self, $detail, @expected_ids) = @_;
    my $result = $self->request('AllStatuses', $detail);
    ## my ($result_code, $result_ref, $mime) = $output->_replyAllStatuses($detail);
    my $detail_str = "";
    while(my ($key, $val) = each(%$detail)) {
        $detail_str .= "$key => $val, ";
    }
    diag(sprintf("checkPagination: output: %s, %s", $self->{output}->getName(), $detail_str));
    is(ref($result), 'ARRAY', 'AllStatuses result is an array ref...');
    cmp_ok(int(@$result), ">=", 3, "and it has at least 3 elements.");
    my %headers = ( @{$result->[1]} );
    ok(defined($headers{'Content-Type'}), 'Content-Type header exists...');
    like($headers{'Content-Type'}, qr(application/json), "and it's JSON.");
    my $got_statuses = JSON::decode_json($result->[2]->[0]);
    is(ref($got_statuses), 'ARRAY', "successfully decoded the JSON to array.");
    cmp_ok(int(@$got_statuses), "==", int(@expected_ids), "number of statuses is what is expected.");
    foreach my $i (0 .. $#expected_ids) {
        is($got_statuses->[$i]->{id}, $expected_ids[$i], "ID is " . $expected_ids[$i]);
    }
}


package main;

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
    my $output_raw;
    eval {
        $output_raw = BusyBird::Output->new();
        fail("Output should not be created without a name.");
    }; if($@) {
        pass("Output should not be created without a name.");
    }
    $output_raw = new_ok('BusyBird::Output', [name => "sample"]);
    is($output_raw->getName, "sample");
    
    my $output_test = BusyBird::Test::Output->new($output_raw);

    diag('------ pushStatuses() should take new statuses.');
    $output_raw->pushStatuses([&generateStatus()]) foreach (1..5);
    $output_test->checkStatusNum(5, 0);
    my @newones = ();
    push(@newones, &generateStatus()) foreach (1..5);
    $output_raw->pushStatuses(\@newones);
    $output_test->checkStatusNum(10, 0);

    diag('------ pushStatuses() should uniqify the input.');
    $output_raw->pushStatuses([&generateStatus($_)]) foreach (1..5);
    $output_test->checkStatusNum(10, 0);

    diag('------ request to Confirm should make new statuses old.');
    $output_test->request('Confirm');
    $output_test->checkStatusNum(0, 10);
    $output_raw->pushStatuses([&generateStatus()]) foreach (1..5);
    $output_test->checkStatusNum(5, 10);
    $output_raw->pushStatuses([&generateStatus($_)]) foreach (1..5);
    $output_test->checkStatusNum(5, 10);

    diag('------ request point AllStatuses pagination test.');
    $output_raw->pushStatuses([&generateStatus()]) foreach (1..55);
    $output_test->request('Confirm');
    $output_raw->pushStatuses([&generateStatus()]) foreach (1..65);
    $output_test->checkStatusNum(65, 70);
    
    diag('------ --- Without per_page option, page 1 always includes all of the new statuses. Old statuses are separated by default per_page value.');
    $output_test->checkPagination({}, reverse(51 .. 135));
    $output_test->checkPagination({page => 0}, reverse(51 .. 135));
    $output_test->checkPagination({page => 1}, reverse(51 .. 135));
    $output_test->checkPagination({page => 2}, reverse(31 .. 50));
    $output_test->checkPagination({page => 3}, reverse(11 .. 30));
    $output_test->checkPagination({page => 4}, reverse(1  .. 10));
    $output_test->checkPagination({page => 5}, ());
    $output_test->checkPagination({max_id => 100, page => 1}, reverse(51 .. 100));
    $output_test->checkPagination({max_id => 100, page => 2}, reverse(31 .. 50));
    $output_test->checkPagination({max_id => 100, page => 3}, reverse(11 .. 30));
    $output_test->checkPagination({max_id => 100, page => 4}, reverse(1  .. 10));
    $output_test->checkPagination({max_id => 100, page => 5}, ());
    $output_test->checkPagination({max_id => 60,  page => 1}, reverse(41 .. 60));
    $output_test->checkPagination({max_id => 60,  page => 2}, reverse(21 .. 40));
    $output_test->checkPagination({max_id => 60,  page => 3}, reverse(1 .. 20));
    $output_test->checkPagination({max_id => 60,  page => 4}, ());

    diag('------ --- With per_page option, new and old statuses are treated as a single status line.');
    $output_test->checkPagination({per_page => 30, page => 0}, reverse(106 .. 135));
    $output_test->checkPagination({per_page => 30, page => 1}, reverse(106 .. 135));
    $output_test->checkPagination({per_page => 30, page => 2}, reverse(76 .. 105));
    $output_test->checkPagination({per_page => 30, page => 3}, reverse(46 .. 75));
    $output_test->checkPagination({per_page => 30, page => 4}, reverse(16 .. 45));
    $output_test->checkPagination({per_page => 30, page => 5}, reverse(1  .. 15));
    $output_test->checkPagination({per_page => 30, page => 6}, ());
    $output_test->checkPagination({per_page => 100, page => 1}, reverse(36 .. 135));
    $output_test->checkPagination({per_page => 100, page => 2}, reverse(1 .. 35));
    $output_test->checkPagination({per_page => 100, page => 3}, ());
    $output_test->checkPagination({per_page => 500, page => 1}, reverse(1 .. 135));
    $output_test->checkPagination({per_page => 500, page => 2}, ());
    $output_test->checkPagination({max_id => 125, per_page => 40, page => 1}, reverse(86 .. 125));
    $output_test->checkPagination({max_id => 125, per_page => 40, page => 2}, reverse(46 .. 85));
    $output_test->checkPagination({max_id => 125, per_page => 40, page => 3}, reverse(6  .. 45));
    $output_test->checkPagination({max_id => 125, per_page => 40, page => 4}, reverse(1  .. 5));
    $output_test->checkPagination({max_id => 125, per_page => 40, page => 5}, ());
    $output_test->checkPagination({max_id => 60, per_page => 40, page => 1}, reverse(21 .. 60));
    $output_test->checkPagination({max_id => 60, per_page => 40, page => 2}, reverse(1  .. 20));
    $output_test->checkPagination({max_id => 60, per_page => 40, page => 3}, ());

    diag('------ --- With invalid max_id option, pagination should start from index 0');
    $output_test->checkPagination({max_id => 'this_does_not_exist', page => 1}, reverse(51 .. 135));
    $output_test->checkPagination({max_id => 'this_does_not_exist', page => 2}, reverse(31 .. 50));
    
    done_testing();
}

&main();

