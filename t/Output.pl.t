#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;
use Test::AnyEvent::Time;

BEGIN {
    use_ok('IO::File');
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('DateTime');
    use_ok('BusyBird::Status');
    use_ok('BusyBird::Output');
}

sub readFile {
    my ($filepath) = @_;
    my $file = IO::File->new();
    if(!$file->open($filepath, "r")) {
        die "Cannot open $filepath: $!";
    }
    my $data;
    {
        local $/ = undef;
        $data = $file->getline();
    }
    $file->close();
    return $data;
}

sub checkStatusNum {
    my ($output, $expected_new_num, $expected_old_num) = @_;
    my $new_entries = $output->getNewStatuses();
    my $old_entries = $output->getOldStatuses();
    cmp_ok(int(@$new_entries), '==', $expected_new_num, sprintf("number of new_statuses in %s", $output->getName));
    cmp_ok(int(@$old_entries), '==', $expected_old_num, sprintf("number of old_statuses in %s", $output->getName));
    ok($_->{busybird}{is_new}, "this status is new") foreach @$new_entries;
    ok(!$_->{busybird}{is_new}, "this status is old") foreach @$old_entries;
}

sub pushStatusesSync {
    my ($output, $statuses, $timeout) = @_;
    $timeout ||= 10;
    time_within_ok sub {
        my $cv = shift;
        $cv->begin();
        $output->pushStatuses($statuses, sub { $cv->end() });
    }, $timeout;
}

sub checkPagination {
    my ($output, $detail, @expected_ids) = @_;
    my $got_statuses = $output->getPagedStatuses(%$detail);
    ## my ($result_code, $result_ref, $mime) = $output->_replyAllStatuses($detail);
    my $detail_str = "";
    while(my ($key, $val) = each(%$detail)) {
        $detail_str .= sprintf("$key => %s, ", defined($val) ? $val : '[undef]');
    }
    note(sprintf("checkPagination: output: %s, %s", $output->getName(), $detail_str));
    ## is(ref($result), 'ARRAY', 'AllStatuses result is an array ref...');
    ## cmp_ok(int(@$result), ">=", 3, "and it has at least 3 elements.");
    ## my %headers = ( @{$result->[1]} );
    ## ok(defined($headers{'Content-Type'}), 'Content-Type header exists...');
    ## like($headers{'Content-Type'}, qr(application/json), "and it's JSON.");
    ## my $got_statuses = JSON::decode_json($result->[2]->[0]);
    is(ref($got_statuses), 'ARRAY', "returned an array-ref");
    cmp_ok(int(@$got_statuses), "==", int(@expected_ids), "number of statuses is what is expected.");
    foreach my $i (0 .. $#expected_ids) {
        is($got_statuses->[$i]->{id}, $expected_ids[$i], "ID is " . $expected_ids[$i]);
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
        id_str => "$id",
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
                    is($statuses->[$i]->{id}, $expected_ids->[$i], "status ID $expected_ids->[$i]");
                    foreach my $field (@$check_fields) {
                        ok(defined($statuses->[$i]->{$field}), "$field is defined...");
                        is($statuses->[$i]->{$field}, $expected_ids->[$i], "and is expected status ID.");
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
                    $status->{$field_name} = $status->{id};
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
    
    note('------ pushStatuses() should take new statuses.');
    
    &pushStatusesSync($output, [&generateStatus()]) foreach (1..5);
    &checkStatusNum($output, 5, 0);
    my @newones = ();
    push(@newones, &generateStatus()) foreach (1..5);
    &pushStatusesSync($output, \@newones);
    &checkStatusNum($output, 10, 0);

    note('------ pushStatuses() should uniqify the input.');
    time_within_ok sub {
        my $cv = shift;
        foreach (1..5) {
            $cv->begin();
            $output->pushStatuses([&generateStatus($_)], sub { $cv->end() });
        }
    }, 10;
    &checkStatusNum($output, 10, 0);

    note('------ confirm() should make new statuses old.');
    $output->confirm();
    &checkStatusNum($output, 0, 10);
    &pushStatusesSync($output, [&generateStatus()]) foreach (1..5);
    &checkStatusNum($output, 5, 10);
    &pushStatusesSync($output, [&generateStatus($_)]) foreach (1..5);
    &checkStatusNum($output, 5, 10);

    note('------ getPagedStatuses() pagination test.');
    &pushStatusesSync($output, [&generateStatus()]) foreach (1..55);
    $output->confirm();
    &pushStatusesSync($output, [&generateStatus()]) foreach (1..65);
    &checkStatusNum($output, 65, 70);
    
    note('------ --- Without per_page option, page 1 always includes all of the new statuses. Old statuses are separated by the default per_page value.');
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

    note('------ --- With per_page option, new and old statuses are treated as a single status line.');
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

    note('------ --- With invalid max_id option, pagination should start from index 0');
    &checkPagination($output, {max_id => 'this_does_not_exist', page => 1}, reverse(51 .. 135));
    &checkPagination($output, {max_id => 'this_does_not_exist', page => 2}, reverse(31 .. 50));

    note('------ --- With invalid per_page option, pagination falls back to the default.');
    &checkPagination($output, {page => 1, per_page => 'not_a_number'}, reverse(51 .. 135));
    &checkPagination($output, {page => 2, per_page => undef}, reverse(31 .. 50));
    &checkPagination($output, {page => 2, per_page => -10}, reverse(31 .. 50));
    &checkPagination($output, {page => 3, per_page => 0}, reverse(11 .. 30));
    &checkPagination($output, {page => 3, per_page => 1}, (133));

    note('------ --- With invalid page option, it is considered to be 0.');
    &checkPagination($output, {page => 'not_a_number', max_id => 100}, reverse(51 .. 100));
    &checkPagination($output, {page => undef, max_id => 100}, reverse(51 .. 100));
    &checkPagination($output, {page => -1, max_id => 100}, reverse(51 .. 100));

    note('------ --- since_id option controls the oldest status returned');
    &checkPagination($output, {since_id => 10}, reverse(51 .. 135));
    &checkPagination($output, {since_id => 50}, reverse(51 .. 135));
    &checkPagination($output, {since_id => 100}, reverse(101 .. 135));
    &checkPagination($output, {since_id => 51}, reverse(52 .. 135));
    &checkPagination($output, {since_id => 135}, ());
    &checkPagination($output, {since_id => 136}, reverse(51 .. 135));
    &checkPagination($output, {since_id => undef}, reverse(51 .. 135));
    &checkPagination($output, {since_id => 'this_does_not_exist'}, reverse(51 .. 135));
    &checkPagination($output, {page => 2, since_id => 40}, reverse(41 .. 50));
    &checkPagination($output, {page => 2, since_id => 10}, reverse(31 .. 50));
    &checkPagination($output, {page => 2, since_id => 49}, (50));
    &checkPagination($output, {page => 2, since_id => 50}, ());
    &checkPagination($output, {page => 2, since_id => 100}, ());
    &checkPagination($output, {page => 3, since_id => 10}, reverse(11 .. 30));
    &checkPagination($output, {page => 3, since_id => 40}, ());
    &checkPagination($output, {page => 3, since_id => 130}, ());
    &checkPagination($output, {page => 3, since_id => 136}, reverse(11 .. 30));
    &checkPagination($output, {max_id => 100, page => 1, since_id => 65}, reverse(66 .. 100));
    &checkPagination($output, {max_id => 100, page => 1, since_id => 100}, ());
    &checkPagination($output, {max_id => 100, page => 1, since_id => 120}, ());
    &checkPagination($output, {max_id => 100, page => 1, since_id => 140}, reverse(51 .. 100));
    &checkPagination($output, {max_id => 100, page => 2, since_id => 65}, ());
    &checkPagination($output, {max_id => 60, page => 1, since_id => 30}, reverse(41 .. 60));
    &checkPagination($output, {max_id => 60, page => 2, since_id => 30}, reverse(31 .. 40));
    &checkPagination($output, {max_id => 60, page => 3, since_id => 30}, ());
    &checkPagination($output, {per_page => 40, page => 1, since_id => 93}, reverse(96 .. 135));
    &checkPagination($output, {per_page => 40, page => 2, since_id => 93}, reverse(94 .. 95));
    &checkPagination($output, {per_page => 40, page => 3, since_id => 93}, ());
    &checkPagination($output, {per_page => 40, page => 4, since_id => 93}, ());
    &checkPagination($output, {per_page => 40, page => 4, since_id => 2000}, reverse(1 .. 15));
    &checkPagination($output, {per_page => 500, page => 1, since_id => 10}, reverse(11 .. 135));
    &checkPagination($output, {per_page => 500, page => 2, since_id => 10}, ());
    &checkPagination($output, {max_id => 125, per_page => 40, since_id => 32, page => 1}, reverse(86 .. 125));
    &checkPagination($output, {max_id => 125, per_page => 40, since_id => 32, page => 2}, reverse(46 .. 85));
    &checkPagination($output, {max_id => 125, per_page => 40, since_id => 32, page => 3}, reverse(33 .. 45));
    &checkPagination($output, {max_id => 125, per_page => 40, since_id => 32, page => 4}, ());

    {
        note('------ Test Output filters');
        $output = new_ok('BusyBird::Output', [name => 'filter_test']);
        $next_id = 1;
        my ($count_input, $count_new) = (0, 0);
        $output->getInputFilter()->push(&filterCheckParallelBegin());
        $output->getInputFilter()->push(&filterCount(\$count_input));
        $output->getInputFilter()->push(&filterSleep(0.3));
        $output->getNewStatusFilter()->push(&filterCount(\$count_new));
        $output->getNewStatusFilter()->push(&filterCheckParallelEnd());
        my @input_statuses = map {&generateStatus()} 1..20;
        &pushStatusesSync($output, \@input_statuses);
        cmp_ok($count_input, "==", 20, "20 statuses went through InputFilter");
        cmp_ok($count_new, '==', 20, '20 statuses went through NewStatusFilter');

        ($count_input, $count_new) = (0, 0);
        time_within_ok sub {
            my $cv = shift;
            foreach (1..20) {
                $cv->begin();
                $output->pushStatuses([&generateStatus()], sub { $cv->end() });
            }
        }, 10;
        cmp_ok($count_input, "==", 20, "20 statuses went through InputFilter");
        cmp_ok($count_new, "==", 20, "20 statuses went through NewStatusFilter");
    }

    {
        note('------ Test save and load status file');
        $output = new_ok('BusyBird::Output', [name => 'save_load_test']);
        &pushStatusesSync($output, [map {&generateStatus()} 1..20]);
        $output->confirm;
        &pushStatusesSync($output, [map {&generateStatus()} 1..10]);
        &checkStatusNum($output, 10, 20);
        my $filepath = $output->_getStatusesFilePath;
        eval {
            like($filepath, qr/statuses\.json$/, "Statuses file path $filepath seems correct.") or die "";
            ok(unlink($filepath), "remove $filepath") if -f $filepath;
            $output->saveStatuses();
            ok(-r $filepath, "Statuses file $filepath created.") or die "";
            my $before_savedfile = &readFile($filepath);
            $output = new_ok('BusyBird::Output', [name => 'save_load_test']);
            &checkStatusNum($output, 0, 0);
            $output->loadStatuses();
            &checkStatusNum($output, 10, 20);
            $output->saveStatuses();
            my $after_savedfile = &readFile($filepath);
            is($after_savedfile, $before_savedfile, "The serialization is consistent.");
        };
        ok(!$@, "save and load status file test successful");
        ok(unlink($filepath), "remove $filepath") if -f $filepath;
    }

    {
        note('------ Test sync_with_input option.');
        $output = new_ok('BusyBird::Output', [name => 'test_sync', sync_with_input => 1]);
        $next_id = 1;
        foreach (1..5) {
            &pushStatusesSync($output, [&generateStatus()]);
            &checkStatusNum($output, 1, 0);
        }
        &pushStatusesSync($output, [map {&generateStatus()} (1..10)]);
        &checkStatusNum($output, 10, 0);
        &pushStatusesSync($output, [map {&generateStatus($_)} (10 .. 15)]);
        &checkStatusNum($output, 6, 0);
        $output->confirm();
        &checkStatusNum($output, 0, 6);
        &pushStatusesSync($output, [map {&generateStatus($_)} (13 .. 18)]);
        &checkStatusNum($output, 3, 3);
        &pushStatusesSync($output, [map {&generateStatus($_)} (20 .. 29)]);
        &checkStatusNum($output, 10, 0);
    }

    {
        note('------ Test auto_confirm option.');
        $output = new_ok('BusyBird::Output', [name => 'test_auto_confirm', auto_confirm => 1]);
        $next_id = 1;
        foreach my $num (1..5) {
            &pushStatusesSync($output, [&generateStatus()]);
            &checkStatusNum($output, 0, $num);
        }
        &pushStatusesSync($output, [map {&generateStatus()} (1..10)]);
        &checkStatusNum($output, 0, 15);
        &pushStatusesSync($output, [map {&generateStatus($_)} (10 .. 25)]);
        &checkStatusNum($output, 0, 25);
    }
    
    done_testing();
}

&main();

