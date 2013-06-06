use strict;
use warnings;
use Test::More;
use FindBin;
use lib ("$FindBin::RealBin/../t/lib");
use BusyBird::Test::Input_Twitter qw(:all);
use BusyBird::Log;
use utf8;

BEGIN {
    use_ok('BusyBird::Input::Twitter');
}

$BusyBird::Log::Logger = undef;

my $mocknt = mock_twitter();

note('--- AUTHOR TEST: filepath option');
my $filename = "test_persistence_file_input_twitter";
if(-r $filename) {
    fail("$filename exists before test. Test aborted.");
    exit(1);
}
my $bbin = BusyBird::Input::Twitter->new(
    backend => $mocknt, filepath => $filename, page_next_delay => 0,
    transformer => \&negative_id_transformer
);
$mocknt->clear;
is_deeply(
    $bbin->user_timeline({max_id => 30, since_id => 5, count => 20, user_id => 88}),
    [statuses -30..-6],
    "user_timeline: init"
);
test_call $mocknt, 'user_timeline', {user_id => 88, count => 20, since_id => 5, max_id => 30};
test_call $mocknt, 'user_timeline', {user_id => 88, count => 20, since_id => 5, max_id => 11};
test_call $mocknt, 'user_timeline', {user_id => 88, count => 20, since_id => 5, max_id => 6};
end_call $mocknt;
    
ok(-r $filename, "$filename created");

$mocknt->clear;
is_deeply(
    $bbin->user_timeline({max_id => 70, count => 35, user_id => 88}),
    [statuses -70..-31],
    "user_timmeline: from the previous max_id"
);
test_call $mocknt, 'user_timeline', {user_id => 88, count => 35, since_id => 30, max_id => 70};
test_call $mocknt, 'user_timeline', {user_id => 88, count => 35, since_id => 30, max_id => 36};
test_call $mocknt, 'user_timeline', {user_id => 88, count => 35, since_id => 30, max_id => 31};
end_call $mocknt;

$mocknt->clear;
is_deeply(
    $bbin->user_timeline({count => 5, screen_name => "hoge"}),
    [statuses -100..-96],
    "user_timeline: different label"
);
test_call $mocknt, "user_timeline", {count => 5, screen_name => 'hoge'};
end_call $mocknt;

$mocknt->clear;
is_deeply(
    $bbin->search({q => 'ほ げ', max_id => 60, count => 10}),
    [statuses -60..-51],
    "search: hoge first"
);
test_call $mocknt, "search", {q => 'ほ げ', count => 10, max_id => 60};
end_call $mocknt;

$mocknt->clear;
is_deeply(
    $bbin->search({q => 'ふーばー', count => 10}),
    [statuses -100..-91],
    "search: foobar first"
);
test_call $mocknt, "search", {q => 'ふーばー', count => 10};
end_call $mocknt;

$mocknt->clear;
is_deeply(
    $bbin->search({q => 'ほ げ', count => 30}),
    [statuses -100..-61],
    "search: hoge second. it continues from ID=61"
);
test_call $mocknt, "search", {q => 'ほ げ', count => 30, since_id => 60};
test_call $mocknt, "search", {q => 'ほ げ', count => 30, since_id => 60, max_id => 71};
test_call $mocknt, "search", {q => 'ほ げ', count => 30, since_id => 60, max_id => 61};
end_call $mocknt;

ok(-r $filename, "$filename exists");
unlink($filename);

done_testing();


