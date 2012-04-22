#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok('AnyEvent');
    use_ok('AnyEvent::Strict');
    use_ok('BusyBird::Status');
    use_ok('BusyBird::Input::Test');
}

sub createInput {
    my ($interval, $count, $page, $cv) = @_;
    my $input = new_ok('BusyBird::Input::Test', [
        name => 'test', no_timefile => 1, new_interval => $interval,
        new_count => $count, page_num => $page
    ]);
    $input->listenOnGetStatuses(
        sub {
            my ($statuses) = @_;
            ok(defined($statuses));
            cmp_ok(int(@$statuses), '==', $count * $page);
            foreach my $status (@$statuses) {
                like($status->get('id'), qr(^Test));
                is($status->get('user/screen_name'), 'Test');
            }
            $cv->end();
        }
    );
    return $input;
}

sub triggerGet {
    my ($input, $cv) = @_;
    $cv->begin();
    $input->getStatuses();
}

my $cv = AnyEvent->condvar;
my $input = &createInput(1, 1, 1, $cv);

&triggerGet($input, $cv);
&triggerGet($input, $cv);
&triggerGet($input, $cv);
&triggerGet($input, $cv);
&triggerGet($input, $cv);

$cv->recv();

done_testing();
