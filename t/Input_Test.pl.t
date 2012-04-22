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
    use_ok('BusyBird::Input::Test');
}

my $TRIGGER_DELAY = 2;
my $total_actual_fire = 0;
my $total_expect_fire = 0;
my $gcv;


sub createInput {
    my (%params_arg) = @_;
    my %params = (
        name => 'test', no_timefile => 1,
        new_interval => 1, new_count => 1, page_num => 1,
        %params_arg,
    );
    my $input = new_ok('BusyBird::Input::Test', [ %params ]);
    my ($interval, $count, $page_num, $page_noth_max) =
        @params{qw(new_interval new_count page_num page_no_threshold_max)};
    my $fire_count = 0;
    $input->listenOnGetStatuses(
        sub {
            my ($statuses) = @_;
            $total_actual_fire++;
            diag("OnGetStatuses (interval => $interval, count => $count, page_num => $page_num)");
            my $expect_page_num = ($fire_count == 0 and $page_noth_max < $page_num) ? $page_noth_max : $page_num;
            ok(defined($statuses));
            cmp_ok(int(@$statuses), '==', $count * $expect_page_num);
            my $expect_index = 0;
            my $expect_page = 0;
            foreach my $status (@$statuses) {
                like($status->get('id'), qr(^Test));
                is($status->get('user/screen_name'), 'Test');
                my $text_obj = decode_json($status->get('text'));
                cmp_ok($text_obj->{index}, '==', $expect_index, "index == $expect_index");
                cmp_ok($text_obj->{page}, '==', $expect_page, "page == $expect_page");
                if($expect_index == $count - 1) {
                    $expect_index = 0;
                    $expect_page++;
                }else {
                    $expect_index++;
                }
            }
            $fire_count++;
            $gcv->end();
        }
    );
    my $trigger_func = sub {
        my (%param) = @_;
        my $diag_str = "Trigger (interval => $interval, count => $count, page_num => $page_num)";
        if($param{expect_fire}) {
            $gcv->begin();
            $total_expect_fire++;
            $diag_str .= ": expect_fire";
        }
        diag($diag_str);
        $gcv->begin();
        my $timer; $timer = AnyEvent->timer(
            after => $TRIGGER_DELAY,
            cb => sub {
                undef $timer;
                $gcv->end();
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


diag("----- test for number of statuses loaded.");
sync 10, sub {
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
            $trigger->(expect_fire => ($trigger_count % $param_set->{new_interval} == 0));
        }
    }
};


diag("----- test for timestamp and threshold management.");
my ($trigger, $input);
my $old_time = DateTime->now() - DateTime::Duration->new(years => 3);
sync 10, sub {
    ($trigger, $input) = &createInput(
        new_interval => 2, new_count => 3, page_num => 3, page_no_threshold_max => 2,
    );
    $input->setTimeStamp($old_time);
    $trigger->(expect_fire => 1);
    $trigger->(expect_fire => 0);
    $trigger->(expect_fire => 1);
    $trigger->(expect_fire => 0);
    diag("Initiate Input with old_time");
};

sync 10, sub {
    $input->setTimeStamp(DateTime->now());
    $trigger->(expect_fire => 1);
    $trigger->(expect_fire => 0);
    $trigger->(expect_fire => 1);
    $trigger->(expect_fire => 0);
    $trigger->(expect_fire => 1);
    diag("Set Input timestamp to the current time.");
};

sync 10, sub {
    $input->setTimeStamp($old_time);
    $trigger->(expect_fire => 0) foreach 1..5;
    diag("Set Input timestamp to the old_time");
};

sync 10, sub {
    $input->setTimeStamp(undef);
    $trigger->(expect_fire => 1);
    $trigger->(expect_fire => 0);
    $trigger->(expect_fire => 1);
    $trigger->(expect_fire => 0);
    diag("Set Input timestamp to undef");
};

done_testing();
