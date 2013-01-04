package Test::App::BusyBird::StatusStorage;
use strict;
use warnings;
use Exporter qw(import);
use DateTime;
use Test::More;
use Test::Builder;
use App::BusyBird::DateTime::Format;
use Carp;

our @EXPORT = qw(test_status_storage);

my $datetime_formatter = 'App::BusyBird::DateTime::Format';

sub status {
    my ($id, $level, $confirmed_at) = @_;
    croak "you must specify id" if not defined $id;
    my $status = {
        id => $id,
        created_at => $datetime_formatter->format_datetime(
            DateTime->from_epoch(epoch => $id)
        ),
    };
    $status->{busybird}{level} = $level if defined $level;
    $status->{busybird}{confirmed_at} = $confirmed_at if defined $confirmed_at;
    return $status;
}

sub id_counts {
    my @statuses_or_ids = @_;
    my %id_counts = ();
    foreach my $s_id (@statuses_or_ids) {
        my $id = ref($s_id) ? $s_id->{id} : $s_id;
        $id_counts{$id} += 1;
    }
    return %id_counts;
}

sub test_status_id_set {
    ## unordered status ID set test
    my ($got_statuses, $exp_statuses_or_ids, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is_deeply(
        { id_counts @$got_statuses },
        { id_counts @$exp_statuses_or_ids },
        $msg
    );
}

sub sync_get {
    my ($storage, $loop, $unloop, %query) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $callbacked = 0;
    my $statuses;
    $storage->get_statuses(%query, callback => sub {
        is(int(@_), 1, 'operation succeed');
        $statuses = $_[0];
        $callbacked = 1;
        $unloop->();
    });
    $loop->();
    ok($callbacked, 'callbacked');
    return $statuses;
}

sub on_statuses {
    my ($storage, $loop, $unloop, $query_ref, $code) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    $code->(sync_get($storage, $loop, $unloop, %$query_ref));
}


sub test_status_storage {
    my ($storage, $loop, $unloop) = @_;
    $loop ||= sub {};
    $unloop ||= sub {};
    my $callbacked = 0;
    note("--- clear the timelines");
    foreach my $tl ('_test_tl1', "_test_tl2", "_test_time line") {
        $callbacked = 0;
        $storage->delete_statuses(
            timeline => $tl,
            callback => sub {
                $callbacked = 1;
                $unloop->();
            }
        );
        $loop->();
        ok($callbacked, "callbacked");
        is_deeply(
            { $storage->get_unconfirmed_counts(timeline => $tl) },
            { total => 0 },
            "$tl is empty"
        );
    }
    
    note("--- put_statuses (insert), single");
    $callbacked = 0;
    $storage->put_statuses(
        timeline => '_test_tl1',
        mode => 'insert',
        statuses => status(1),
        callback => sub {
            my ($num, $error) = @_;
            is(int(@_), 1, 'put_statuses succeed.');
            is($num, 1, 'put 1 status');
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    is_deeply(
        { $storage->get_unconfirmed_counts(timeline => '_test_tl1') },
        { total => 1, 0 => 1 },
        '1 unconfirmed status'
    );
    note('--- put_statuses (insert), multiple');
    $callbacked = 0;
    $storage->put_statuses(
        timeline => '_test_tl1',
        mode => 'insert',
        statuses => [map { status($_) } 2..5],
        callback => sub {
            my ($num, $error) = @_;
            is(int(@_), 1, 'put_statuses succeed');
            is($num, 4, 'put 4 statuses');
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    is_deeply(
        { $storage->get_unconfirmed_counts(timeline => '_test_tl1') },
        { total => 5, 0 => 5 },
        '5 unconfirmed status'
    );

    note('--- get_statuses');
    $callbacked = 0;
    $storage->get_statuses(
        timeline => '_test_tl1',
        count => 'all',
        callback => sub {
            my ($statuses, $error) = @_;
            is(int(@_), 1, "get_statuses succeed");
            test_status_id_set($statuses, [1..5], "1..5 statuses");
            foreach my $s (@$statuses) {
                no autovivification;
                ok(!$s->{busybird}{confirmed_at}, "status is not confirmed");
            }
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");

    note('--- confirm_statuses');
    $callbacked = 0;
    $storage->confirm_statuses(
        timeline => '_test_tl1',
        callback => sub {
            my ($num, $error) = @_;
            is(int(@_), 1, "confirm_statuses succeed");
            is($num, 5, "5 statuses confirmed.");
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    is_deeply(
        { $storage->get_unconfirmed_counts(timeline => '_test_tl1') },
        { total => 0 },
        "all confirmed"
    );
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl1', count => 'all'
    }, sub {
        my $statuses = shift;
        is(int(@$statuses), 5, "5 statueses");
        foreach my $s (@$statuses) {
            no autovivification;
            ok($s->{busybird}{confirmed_at}, 'confirmed');
        }
    };

    note('--- delete_statuses (single deletion)');
    $callbacked = 0;
    $storage->delete_statuses(
        timeline => '_test_tl1',
        ids => 3,
        callback => sub {
            my ($num, $error) = @_;
            is(int(@_), 1, "operation succeed.");
            is($num, 1, "1 deletion");
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl1', count => 'all'
    }, sub {
        my $statuses = shift;
        test_status_id_set($statuses, [1,2,4,5], "ID=3 is deleted");
    };

    note('--- delete_statuses (multiple deletion)');
    $callbacked = 0;
    $storage->delete_statuses(
        timeline => '_test_tl1',
        ids => [1, 4],
        callback => sub {
            my ($num, $error) = @_;
            is(int(@_), 1, 'operation succeed');
            is($num, 2, "2 statuses deleted");
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl1', count => 'all'
    }, sub {
        my $statuses = shift;
        test_status_id_set($statuses, [2,5], "ID=1,4 are deleted");
    };

    note('--- delete_statuses (all deletion)');
    $callbacked = 0;
    $storage->delete_statuses(
        timeline => '_test_tl1',
        ids => undef,
        callback => sub {
            my ($num, $error) = @_;
            is(int(@_), 1, 'operation succeed');
            is($num, 2, "2 statuses deleted");
            $callbacked = 1;
            $unloop->();
        }
    );
    $loop->();
    ok($callbacked, "callbacked");
    on_statuses $storage, $loop, $unloop, {
        timeline => '_test_tl1', count => 'all'
    }, sub {
        my $statuses = shift;
        test_status_id_set($statuses, [], "ID=2,5 are deleted. now empty");
    };
    

  TODO: {
        local $TODO = "tests are going to be written.";
        fail('put_statuses (insert): insert duplicate IDs');
        fail('put_statuses (insert): insert confirmed statuses');
        fail('put_statuses (update): non-existent statuses');
        fail('get_unconfirmed_counts: multi level unconfirmed');
        fail('get_statuses: max_id, count');
        fail('delete_statuses: non-existent statuses');
        fail('timeline independency');
        ## We do not test error mode cases here(?). It depends on implementations.
    }
}

=pod

=head1 NAME

Test::App::BusyBird::StatusStorage - Test routines for StatusStorage

=head1 FUNCTION

=head2 test_status_storage($storage, $loop, $unloop)

Test the StatusStorage object.

C<$storage> is the StatusStorage object to be tested.
C<$loop> is a subroutine reference to go into the event loop,
C<$unloop> is a subroutine reference to go out of the event loop.
If the storage does not use any event loop mechanism, C<$loop> and <$unloop> can be omitted.

In general test of statuses are based on status IDs.
This allows implementations to modify statuses internally.
In addition, statuses are tested unordered.

=cut


1;

