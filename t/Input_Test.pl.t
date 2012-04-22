#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('JSON');
    use_ok('BusyBird::Status');
    use_ok('BusyBird::Input::Test');
}

sub createInput {
    my ($cv, %params_arg) = @_;
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
            $cv->end();
        }
    );
    my $trigger_count = 0;
    my $trigger_func = sub {
        $trigger_count++;
        my $diag_str = "Trigger (interval => $interval, count => $count, page_num => $page_num)";
        if(($trigger_count - 1) % $interval == 0) {
            $cv->begin();
            $diag_str .= ": begin";
        }
        diag($diag_str);
        my $timer; $timer = AnyEvent->timer(
            after => 1,
            cb => sub {
                undef $timer;
                $input->getStatuses();
            },
        );
    };
    return $trigger_func;
}

my $cv = AnyEvent->condvar;

my $tw; $tw = AnyEvent->timer(
    after => 10,
    cb => sub {
        undef $tw;
        fail('Takes too long time. Abort.');
        $cv->send();
    }
);

foreach my $param_set (
    {new_interval => 1, new_count => 1, page_num => 1, page_no_threshold_max => 50},
    {new_interval => 1, new_count => 5, page_num => 1, page_no_threshold_max => 50},
    {new_interval => 1, new_count => 2, page_num => 3, page_no_threshold_max => 50},
    {new_interval => 3, new_count => 2, page_num => 1, page_no_threshold_max => 50},
    {new_interval => 2, new_count => 2, page_num => 3, page_no_threshold_max => 50},
    {new_interval => 2, new_count => 1, page_num => 5, page_no_threshold_max => 1},
) {
    my $trigger = &createInput($cv, %$param_set);
    $trigger->() foreach 1..5;
}

$cv->recv();
undef $tw;

done_testing();
