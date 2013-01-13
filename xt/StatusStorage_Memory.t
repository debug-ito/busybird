use v5.10.1;
use strict;
use warnings;
use Test::More;
use Test::Builder;
use App::BusyBird::StatusStorage::Memory;
use App::BusyBird::DateTime::Format;
use DateTime;
use utf8;

sub test_log_contains {
    my ($logs_arrayref, $msg_pattern, $test_msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    ok(
        scalar(grep { $_->[1] ~~ $msg_pattern } @$logs_arrayref),
        $test_msg
    );
}

sub status {
    my ($id) = @_;
    return {
        id => $id, text => "てくすと $_",
        created_at => App::BusyBird::DateTime::Format->format_datetime(
            DateTime->from_epoch(epoch => $id, time_zone => 'UTC')
        )
    };
}

my @logs = ();
my $filepath = 'test_status_storage_memory.json';
if(-r $filepath) {
    fail("$filepath exists before test. Test aborted.");
    exit(1);
}

{
    my $storage = new_ok('App::BusyBird::StatusStorage::Memory', [
        filepath => $filepath,
        logger => sub { push(@logs, [@_]) },
    ]);
    test_log_contains \@logs, qr{cannot.*read}i, "fails to load from $filepath";
    $storage->put_statuses(
        timeline => "hoge_tl", mode => 'insert',
        statuses => [ map { status($_) } 1..10 ],
    );
    ok($storage->save(), "save() succeed");
    ok((-r $filepath), "$filepath is created");
    
    $storage->put_statuses(
        timeline => "hoge_tl", mode => "insert",
        statuses => [ map { status($_) } 50..55 ]
    );

    {
        my $another_storage = new_ok('App::BusyBird::StatusStorage::Memory', [
            filepath => $filepath, logger => undef
        ]);
        my $callbacked = 0;
        $another_storage->get_statuses(
            timeline => 'hoge_tl', count => 'all', callback => sub {
                my ($statuses) = @_;
                $callbacked = 1;
                is(int(@_), 1, "get_statuses succeed");
                is_deeply($statuses, [map { status($_) } reverse 1..10], "status loaded");
            }
        );
        ok($callbacked, "callbacked");
        $another_storage->put_statuses(
            timeline => 'hoge_tl', mode => 'insert',
            statuses => [ map { status($_) } 11..15 ]
        );
    }

    ok($storage->load(), "load() succeed");
    my $callbacked = 0;
    $storage->get_statuses(
        timeline => 'hoge_tl', count => 'all', callback => sub {
            my ($statuses) = @_;
            is(int(@_), 1, "get_statuses succeed");
            $callbacked = 1;
            is_deeply($statuses, [map { status($_)} reverse 1..15], "statuses loaded and they replaced the current content");
        }
    );
    ok($callbacked, "callbacked");
    $storage->put_statuses(
        timeline => 'hoge_tl', mode => 'insert',
        statuses => [map { status($_) } 31..35]
    );
}

ok((-r $filepath), "$filepath exists");
unlink($filepath);

done_testing();

