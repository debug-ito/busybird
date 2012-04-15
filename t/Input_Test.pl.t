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

sub triggerGet {
    my ($input, $cv) = @_;
    $cv->begin();
    $input->getNewStatuses();
}

my $input = new_ok('BusyBird::Input::Test', [name => 'test', no_timefile => 1]);
my $cv = AnyEvent->condvar;

$input->listenOnNewStatuses(
    sub {
        my ($statuses) = @_;
        ok(defined($statuses));
        cmp_ok(int(@$statuses), '==', 1);
        foreach my $status (@$statuses) {
            like($status->get('id'), qr(^Test));
            is($status->get('user/screen_name'), 'Test');
        }
        $cv->end();
    }
);
&triggerGet($input, $cv);
&triggerGet($input, $cv);
&triggerGet($input, $cv);
&triggerGet($input, $cv);
&triggerGet($input, $cv);

$cv->recv();

done_testing();
