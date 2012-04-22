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
    my ($interval, $count, $page, $cv) = @_;
    my $input = new_ok('BusyBird::Input::Test', [
        name => 'test', no_timefile => 1, new_interval => $interval,
        new_count => $count, page_num => $page,
        page_max => 50,
        page_no_threshold_max => 50,
    ]);
    $input->listenOnGetStatuses(
        sub {
            my ($statuses) = @_;
            diag("OnGetStatuses (interval => $interval, count => $count, page_num => $page)");
            ok(defined($statuses));
            cmp_ok(int(@$statuses), '==', $count * $page);
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
            $cv->end();
        }
    );
    my $fire_count = 0;
    my $trigger_func = sub {
        $fire_count++;
        my $diag_str = "Trigger (interval => $interval, count => $count, page_num => $page)";
        if(($fire_count - 1) % $interval == 0) {
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

foreach my $param_set ([1, 1, 1], [1, 5, 1], [1, 2, 3], [3, 2, 1], [2, 2, 3]) {
    my $trigger = &createInput(@$param_set, $cv);
    $trigger->() foreach 1..5;
}

$cv->recv();
undef $tw;

done_testing();
