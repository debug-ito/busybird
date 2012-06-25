use strict;
use warnings;

use Test::More;
use Test::AnyEvent::Time;

BEGIN {
    use_ok('BusyBird::Worker::Twitter');
    use_ok('BusyBird::Input');
    use_ok('BusyBird::Status');
}

my $env_switch = 'BUSYBIRD_TEST_TWITTER';

my $worker = new_ok('BusyBird::Worker::Twitter', [
    ssl => 0
]);
my $input = new_ok('BusyBird::Input', [
    driver => 'BusyBird::InputDriver::Twitter',
    name => 'test_twitter', no_timefile => 1, worker => $worker,
]);

SKIP: {
    if(!$ENV{$env_switch}) {
        skip "Set $env_switch environment to true to test communication with twitter.com", 1;
    }
    my $result_status;
    time_within_ok sub {
        my $cv = shift;
        $input->fetchStatus(
            '112652479837110273', sub {
                $result_status = shift;
                $cv->send();
            }
        );
    }, 30;
    ok(defined($result_status), 'Got a status');
    isa_ok($result_status, 'BusyBird::Status');
    like($result_status->{id}, qr(112652479837110273$));
    cmp_ok($result_status->{text}, "ne", "");
}

done_testing();



