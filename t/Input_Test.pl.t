#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('JSON');
    use_ok('DateTime');
    use_ok('BusyBird::Status');
    use_ok('BusyBird::Filter');
    use_ok('BusyBird::Input::Test');
}

my $TRIGGER_DELAY = 1;
my $total_actual_fire = 0;
my $total_expect_fire = 0;
my $gcv;


sub createInput {
    my (%params_arg) = @_;
    my %params = (
        name => 'test', no_timefile => 1,
        new_interval => 1, new_count => 1, page_num => 1,
        page_next_delay => 0.5, load_delay => 0.2,
        %params_arg,
    );
    my $input = new_ok('BusyBird::Input::Test', [ %params ]);
    ## my ($interval, $count, $page_num, $page_noth_max) =
    ##     @params{qw(new_interval new_count page_num page_no_threshold_max)};
    ## my $fire_count = 0;
    my @expect_queue = ();
    $input->listenOnGetStatuses(
        sub {
            my ($statuses) = @_;
            $total_actual_fire++;
            diag(sprintf("OnGetStatuses (interval => %s, count => %s, page_num => %s)",
                         @params{qw(new_interval new_count page_num)}));
            cmp_ok(int(@expect_queue), '>', 0, 'there is an expect_queue entry');
            my $expect_entry = shift(@expect_queue);
            ## my $expect_page_num = ($fire_count == 0 and $page_noth_max < $page_num) ? $page_noth_max : $page_num;
            my ($expect_count, $expect_page_num) = @$expect_entry{'count', 'page_num'};
            ok(defined($statuses));
            cmp_ok(int(@$statuses), '==', $expect_count * $expect_page_num);
            my $expect_index = 0;
            my $expect_page = 0;
            foreach my $status (@$statuses) {
                like($status->content->{id}, qr(^Test));
                is($status->content->{user}{screen_name}, 'Test');
                my $text_obj = decode_json($status->content->{text});
                cmp_ok($text_obj->{index}, '==', $expect_index, "index == $expect_index");
                cmp_ok($text_obj->{page}, '==', $expect_page, "page == $expect_page");
                if($expect_index == $expect_count - 1) {
                    $expect_index = 0;
                    $expect_page++;
                }else {
                    $expect_index++;
                }
            }
            ## $fire_count++;
            $gcv->end();
        }
    );
    my $trigger_func = sub {
        my (%trigger_param) = @_;
        diag(sprintf("Trigger (interval => %s, count => %s, page_num => %s)",
                 @params{qw(new_interval new_count page_num)}));
        $gcv->begin(); ## For OnGetStatuses event
        $total_expect_fire++;
        $gcv->begin(); ## For the timer below
        my $timer; $timer = AnyEvent->timer(
            after => $TRIGGER_DELAY,
            cb => sub {
                undef $timer;
                $gcv->end();
                push(@expect_queue, {count => $trigger_param{expect_count}, page_num => $trigger_param{expect_page_num}});
                $input->getStatuses();
            },
        );
    };
    return wantarray ? ($trigger_func, $input) : $trigger_func;
}

sub sync ($&) {
    my ($timeout, $coderef) = @_;
    $gcv = AnyEvent->condvar;
    $gcv->begin();
    my $tw; $tw = AnyEvent->timer(
        after => $timeout,
        cb => sub {
            undef $tw;
            fail('Takes too long time. Abort.');
            $gcv->send();
        }
    );
    $coderef->();
    $gcv->end();
    $gcv->recv();
    undef $tw;
    cmp_ok($total_actual_fire, '==', $total_expect_fire, "expected $total_expect_fire fires.");
}

sync 20, sub {
    diag("----- test for number of statuses loaded.");
    foreach my $param_set (
        {new_interval => 1, new_count => 1, page_num => 1, page_no_threshold_max => 50},
        {new_interval => 1, new_count => 5, page_num => 1, page_no_threshold_max => 50},
        {new_interval => 1, new_count => 2, page_num => 3, page_no_threshold_max => 50},
        {new_interval => 3, new_count => 2, page_num => 1, page_no_threshold_max => 50},
        {new_interval => 2, new_count => 2, page_num => 3, page_no_threshold_max => 50},
        {new_interval => 2, new_count => 1, page_num => 5, page_no_threshold_max => 1},
    ) {
        my $trigger = &createInput(%$param_set);
        foreach my $trigger_count (0 .. 4) {
            ## $trigger->(expect_fire => ($trigger_count % $param_set->{new_interval} == 0));
            my $exp_count = ($trigger_count % $param_set->{new_interval} == 0 ? $param_set->{new_count} : 0);
            my $exp_page_num;
            if($trigger_count == 0) {
                $exp_page_num = $param_set->{page_num} > $param_set->{page_no_threshold_max} ?
                    $param_set->{page_no_threshold_max} : $param_set->{page_num};
            }else {
                $exp_page_num = $param_set->{page_num};
            }
            $trigger->(expect_count => $exp_count, expect_page_num => $exp_page_num);
        }
    }
};


diag("----- test for timestamp and threshold management.");
my ($trigger, $input);
my $old_time = DateTime->now() - DateTime::Duration->new(years => 3);
sync 20, sub {
    ($trigger, $input) = &createInput(
        new_interval => 2, new_count => 3, page_num => 3, page_no_threshold_max => 2,
    );
    $input->setTimeStamp($old_time);
    $trigger->(expect_count => 3, expect_page_num => 2);
    $trigger->(expect_count => 0, expect_page_num => 0);
    $trigger->(expect_count => 3, expect_page_num => 3);
    $trigger->(expect_count => 0, expect_page_num => 0);
    diag("Initiate Input with old_time");
};

sync 20, sub {
    $input->setTimeStamp(DateTime->now());
    $trigger->(expect_count => 3, expect_page_num => 3);
    $trigger->(expect_count => 0, expect_page_num => 0);
    $trigger->(expect_count => 3, expect_page_num => 3);
    $trigger->(expect_count => 0, expect_page_num => 0);
    $trigger->(expect_count => 3, expect_page_num => 3);
    diag("Set Input timestamp to the current time.");
};

sync 20, sub {
    $input->setTimeStamp($old_time);
    $trigger->(expect_count => 0, expect_page_num => 0) foreach 1..5;
    diag("Set Input timestamp to the old_time");
};

sync 20, sub {
    $input->setTimeStamp(undef);
    $trigger->(expect_count => 3, expect_page_num => 3);
    $trigger->(expect_count => 0, expect_page_num => 0);
    $trigger->(expect_count => 3, expect_page_num => 3);
    $trigger->(expect_count => 0, expect_page_num => 0);
    diag("Set Input timestamp to undef");
};

diag("----- test for filtering");
my $filter_executed_num = 0;
sync 20, sub {
    ($trigger, $input) = &createInput(
        new_interval => 1, new_count => 2, page_num => 3, page_no_threshold_max => 2,
    );
    $input->getFilter->push(
        sub {
            my ($statuses, $cb) = @_;
            my $tw; $tw = AnyEvent->timer(
                after => 1,
                cb => sub {
                    undef $tw;
                    $filter_executed_num++;
                    foreach my $status (@$statuses) {
                        is($status->content->{user}{screen_name}, 'Test', 'name is Test before the filter');
                        $status->content->{user}{screen_name} = 'hoge';
                    }
                    $cb->($statuses);
                }
            );
        }
    );
    $input->getFilter->push(
        sub {
            my ($statuses, $cb) = @_;
            my $new_array = [];
            $filter_executed_num++;
            foreach my $status (@$statuses) {
                is($status->content->{user}{screen_name}, 'hoge', 'name is changed by a filter.');
                $status->content->{user}{screen_name} = 'Test';
                push(@$new_array, $status);
            }
            $cb->($new_array);
        }
    );
    $trigger->(expect_count => 2, expect_page_num => 2);
    $trigger->(expect_count => 2, expect_page_num => 3);
};
cmp_ok($filter_executed_num, '==', 4, 'filter is executed properly');

$filter_executed_num = 0;
diag("----- If filter deletes all statuses, OnGetStatuses event occurs with no statuses.");
sync 20, sub {
    ($trigger, $input) = &createInput(
        new_interval => 1, new_count => 3, page_num => 1,
    );
    $input->getFilter->push(
        sub {
            my ($statuses, $cb) = @_;
            cmp_ok(int(@$statuses), '==', 3, 'originally 3 new statuses arrive, but deleted by the filter');
            $filter_executed_num++;
            $cb->([]);
        },
    );
    foreach (1..4) {
        $trigger->(expect_count => 0, expect_page_num => 0);
    }
};
cmp_ok($filter_executed_num, '==', 4, 'filter is executed properly');

{
    my $trigger_num = 3;
    my $second_event_count = 0;
    diag("----- test for multiple listener");
    sync 20, sub {
        ($trigger, $input) = &createInput(
            new_interval => 1, new_count => 2, page_num => 2, page_no_threshold_max => 5,
        );
        $input->listenOnGetStatuses(
            sub {
                my ($statuses) = @_;
                cmp_ok(int(@$statuses), '==', 4);
                $second_event_count++;
            }
        );
        $trigger->(expect_count => 2, expect_page_num => 2) foreach 1..$trigger_num;
    };
    cmp_ok($second_event_count, '==', $trigger_num, 'second listener is executed properly');
}

done_testing();
