use strict;
use warnings;
use Test::More;
use Test::Builder;
use Test::MockObject::Extends;
use BusyBird::Input::Twitter;
use BusyBird::Log;
use Encode;
use Time::HiRes;
use Net::Twitter;
use Net::Twitter::Lite::WithAPIv1_1;
use constant (CONFIG_FILEPATH => $ENV{HOME}.'/.bb_input_twitter_test_config.pl');
use constant (SINCE_ID_FILEPATH => 'input_twitter_test_since_id_file.json');
use constant (ACCESS_DELAY => 1.0);
use utf8;

if(!$ENV{BB_TEST_TWITTER}) {
    plan skip_all => "To test Input::Twitter by connecting twitter.com, set BB_TEST_TWITTER environment.";
    exit 0;
}

sub load_config {
    my ($filename) = @_;
    if(! -r $filename) {
        fail("Cannot find config file $filename.");
        done_testing();
        exit 1;
    }
    return do $filename;
}

sub get_oauth_config {
    my ($config) = @_;
    return (map { $_ => $config->{$_} }
                qw(consumer_key consumer_secret access_token access_token_secret));
}

sub show_statuses {
    my ($statuses) = @_;
    diag(int(@$statuses) . " statuses");
    foreach my $status (@$statuses) {
        diag(sprintf(
            "ID:%s User:%s %s\n", $status->{id_str}, $status->{user}{screen_name},
            Encode::encode('utf8', substr($status->{text}, 0, 20))
          ));
    }
}

sub test_result {
    my ($got_statuses, $label, $method, $exp_min_count) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    ok(defined($got_statuses), "$label: $method loaded") or return;
    cmp_ok(int(@$got_statuses), ">", $exp_min_count, "$label: $method " . int(@$got_statuses) . " statuses loaded.");
    show_statuses($got_statuses);
}

sub test_log_num {
    my ($got_logs, $pattern, $exp_num, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my @entries = grep { $_->[1] =~ $pattern } @$got_logs;
    is(int(@entries), $exp_num, $msg);
}

sub test_backend {
    my ($label, $backend) = @_;
    note("--- test backend $label");
    if(-r SINCE_ID_FILEPATH) {
        fail(SINCE_ID_FILEPATH . " already exists.");
        done_testing();
        exit 1;
    }
    my @logs = ();
    local $BusyBird::Log::Logger = sub {
        my ($level, $msg) = @_;
        push(@logs, [$level, $msg]);
    };
    my $input = new_ok('BusyBird::Input::Twitter', [
        backend => $backend, page_max_no_since_id => 2, page_next_delay => 1,
        filepath => SINCE_ID_FILEPATH,
    ]);

    my %tests = (
        user_timeline => {
            arg => {screen_name => "ariyoshihiroiki", count => 5},
            min_num => 5,
        },
        list_statuses => {
            arg => {owner_screen_name => '30th_sb', slug => 'sbg', count => 5, per_page => 5},
            min_num => 5,
        },
        home_timeline => {
            arg => {include_entities => 1, count => 3},
            min_num => 3,
        },
        favorites => {
            arg => {screen_name => "masason", count => 5},
            min_num => 5,
        },
        mentions => {
            arg => {count => 3},
            min_num => 3,
        },
        retweets_of_me => {
            arg => {count => 3},
            min_num => 3,
        },
        search => {
            arg => {q => 'perl', lang => 'ja', rpp => 5, count => 5},
            min_num => 5,
        },
    );

    foreach my $method_name (keys %tests) {
        my $test_entry = $tests{$method_name};
        note("--- $label - $method_name");
        @logs = ();
        my $statuses = $input->$method_name($test_entry->{arg});
        test_result $statuses, $label, $method_name, $test_entry->{min_num};
        test_log_num \@logs, qr{$method_name}, 2, "$label: $method_name 2 pages loaded";
        $test_entry->{last_id} = $statuses->[0]{id};
        sleep ACCESS_DELAY;
    }
    sleep ACCESS_DELAY;

    note("--- $label: second load");
    foreach my $method_name (keys %tests) {
        my $test_entry = $tests{$method_name};
        @logs = ();
        my $statuses = $input->$method_name($test_entry->{arg});
        ok(defined($statuses), "$label: $method_name second load OK");
        ok(!scalar(grep { $_->{id} eq  $test_entry->{last_id}} @$statuses),
           "$label: $method_name second load does not contain last_id");
        sleep ACCESS_DELAY;
    }

    ok((-r SINCE_ID_FILEPATH), "since_id file exists");
    unlink(SINCE_ID_FILEPATH);
}

my $config = load_config(CONFIG_FILEPATH);

test_backend(
    'Net::Twitter API v1.1', Net::Twitter->new(
        traits => [qw(API::RESTv1_1 OAuth)], ssl => 1,
        ## apiurl => 'https://api.twitter.com/1.1/',
        get_oauth_config($config)
    )
);

sleep ACCESS_DELAY;

test_backend(
    'Net::Twitter::Lite API v1.1', Net::Twitter::Lite::WithAPIv1_1->new(
        ## legacy_lists_api => 0,
        ssl => 1,
        get_oauth_config($config)
    )
);

done_testing();

