#!/usr/bin/perl -w

use strict;
use warnings;
use Test::More;

BEGIN {
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('DateTime');
    use_ok('BusyBird::Test', qw(CV within));
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

sub pushStatusesSync {
    my ($output, $statuses, $timeout) = @_;
    $timeout ||= 10;
    within $timeout, sub {
        CV()->begin();
        $output->pushStatuses($statuses, sub { CV()->end() });
    };
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

sub filterCount {
    my ($counter_ref) = @_;
    return sub {
        my ($statuses, $cb) = @_;
        my $tw; $tw = AnyEvent->timer(
            after => 0,
            cb => sub {
                undef $tw;
                is(ref($statuses), 'ARRAY', "statuses is ARRAY");
                $$counter_ref += int(@$statuses);
                $cb->($statuses);
            }
        );
    };
}

sub filterCheck {
    my ($expected_ids, $check_fields) = @_;
    $check_fields = [] if !defined($check_fields);
    return sub {
        my ($statuses, $cb) = @_;
        my $tw; $tw = AnyEvent->timer(
            after => 0,
            cb => sub {
                undef $tw;
                is(ref($statuses), 'ARRAY', 'got ARRAY in filter');
                cmp_ok(int(@$statuses), '==', int(@$expected_ids), 'number of statuses in filter');
                foreach my $i (0 .. $#$statuses) {
                    is($statuses->[$i]->content->{id}, $expected_ids->[$i], "status ID $expected_ids->[$i]");
                    foreach my $field (@$check_fields) {
                        ok(defined($statuses->[$i]->content->{$field}), "$field is defined...");
                        is($statuses->[$i]->content->{$field}, $expected_ids->[$i], "and is expected status ID.");
                    }
                }
                $cb->($statuses);
            }
        );
    };
}

my $g_parallel_count = 0;

sub filterCheckParallelBegin {
    my $PARALLEL_LIMIT = 1;
    return sub {
        my ($statuses, $cb) = @_;
        my $tw; $tw = AnyEvent->timer(
            after => 0,
            cb => sub {
                undef $tw;
                $g_parallel_count++;
                cmp_ok($g_parallel_count, "<=", $PARALLEL_LIMIT,
                       "filters are executed in parallel with up to $PARALLEL_LIMIT pseudo-threads.");
                $cb->($statuses);
            }
        );
    };
}

sub filterCheckParallelEnd {
    return sub {
        my ($statuses, $cb) = @_;
        my $tw; $tw = AnyEvent->timer(
            after => 0,
            cb => sub {
                undef $tw;
                $g_parallel_count--;
                cmp_ok($g_parallel_count, ">=", 0);
                $cb->($statuses);
            }
        );
    };
}

sub filterField {
    my ($field_name) = @_;
    return sub {
        my ($statuses, $cb) = @_;
        my $tw; $tw = AnyEvent->timer(
            after => 0,
            cb => sub {
                undef $tw;
                foreach my $status (@$statuses) {
                    $status->content->{$field_name} = $status->content->{id};
                }
                $cb->($statuses);
            }
        );
    };
}

sub filterDup {
    my ($factor) = @_;
    return sub {
        my ($statuses, $cb) = @_;
        my $tw; $tw = AnyEvent->timer(
            after => 0,
            cb => sub {
                undef $tw;
                my @duped = ();
                foreach my $status (@$statuses) {
                    foreach (1 .. $factor) {
                        push(@duped, $status->clone());
                    }
                }
                $cb->(\@duped);
            }
        );
    }
}

sub filterDeleteAll {
    return &filterDup(0);
}

sub filterAdd {
    my (@added_ids) = @_;
    return sub {
        my ($statuses, $cb) = @_;
        my $tw; $tw = AnyEvent->timer(
            after => 0,
            cb => sub {
                undef $tw;
                foreach my $id (@added_ids) {
                    push(@$statuses, &generateStatus($id));
                }
                $cb->($statuses);
            }
        );
    };
}

sub filterSleep {
    my ($sleep_time) = @_;
    return sub {
        my ($statuses, $cb) = @_;
        my $tw; $tw = AnyEvent->timer(
            after => $sleep_time,
            cb => sub {
                undef $tw;
                $cb->($statuses);
            }
        );
    };
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
    
    &pushStatusesSync($output, [&generateStatus()]) foreach (1..5);
    &checkStatusNum($output, 5, 0);
    my @newones = ();
    push(@newones, &generateStatus()) foreach (1..5);
    &pushStatusesSync($output, \@newones);
    &checkStatusNum($output, 10, 0);

    diag('------ pushStatuses() should uniqify the input.');
    within 10, sub {
        foreach (1..5) {
            CV()->begin();
            $output->pushStatuses([&generateStatus($_)], sub { CV()->end() });
        }
    };
    &checkStatusNum($output, 10, 0);

    diag('------ _confirm() should make new statuses old.');
    $output->_confirm();
    &checkStatusNum($output, 0, 10);
    &pushStatusesSync($output, [&generateStatus()]) foreach (1..5);
    &checkStatusNum($output, 5, 10);
    &pushStatusesSync($output, [&generateStatus($_)]) foreach (1..5);
    &checkStatusNum($output, 5, 10);

    diag('------ _getPagedStatuses() pagination test.');
    &pushStatusesSync($output, [&generateStatus()]) foreach (1..55);
    $output->_confirm();
    &pushStatusesSync($output, [&generateStatus()]) foreach (1..65);
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

    {
        diag('------ Test Output filters');
        $output = new_ok('BusyBird::Output', [name => 'filter_test']);
        $next_id = 1;
        my ($count_input, $count_new) = (0, 0);
        $output->getInputFilter()->push(&filterCheckParallelBegin());
        $output->getInputFilter()->push(&filterCount(\$count_input));
        $output->getInputFilter()->push(&filterSleep(1));
        $output->getNewStatusFilter()->push(&filterCount(\$count_new));
        $output->getNewStatusFilter()->push(&filterCheckParallelEnd());
        my @input_statuses = map {&generateStatus()} 1..20;
        &pushStatusesSync($output, \@input_statuses);
        cmp_ok($count_input, "==", 20, "20 statuses went through InputFilter");
        cmp_ok($count_new, '==', 20, '20 statuses went through NewStatusFilter');

        ($count_input, $count_new) = (0, 0);
        within 10, sub {
            foreach (1..20) {
                CV()->begin();
                $output->pushStatuses([&generateStatus()], sub { CV()->end() });
            }
        };
        cmp_ok($count_input, "==", 20, "20 statuses went through InputFilter");
        cmp_ok($count_new, "==", 20, "20 statuses went through NewStatusFilter");
    }
    
    done_testing();
}

&main();

