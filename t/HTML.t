use strict;
use warnings;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use Test::More;
use BusyBird::Main;
use BusyBird::Log;
use BusyBird::StatusStorage::Memory;
use Plack::Test;
use BusyBird::Test::HTTP;

$BusyBird::Log::Logger = undef;

{
    my $main = BusyBird::Main->new;
    $main->default_status_storage(BusyBird::StatusStorage::Memory->new);
    $main->timeline('foo');
    $main->timeline('bar');

    test_psgi $main->to_app, sub {
        my $tester = BusyBird::Test::HTTP->new(requester => shift);
        note('--- timeline view');
        foreach my $case (
            {path => '/timelines/foo', exp_timeline => 'foo'},
            {path => '/timelines/foo/', exp_timeline => 'foo'},
            {path => '/timelines/foo/index.html', exp_timeline => 'foo'},
            {path => '/timelines/foo/index.htm', exp_timeline => 'foo'},
            {path => '/timelines/bar/', exp_timeline => 'bar'}
        ) {
            my $tree = $tester->request_htmltree_ok('GET', $case->{path}, undef, qr/^200$/, "$case->{path}: GET OK");
            my ($title_node) = $tree->findnodes('//title');
            my ($title_text) = $title_node->content_list;
            like($title_text, qr/$case->{exp_timeline}/, '... View title OK');
        }

        note('--- not found cases');
        foreach my $case (
            {path => '/timelines/buzz'},
            {path => '/timelines/home/index.html'},
            {path => '/timelines/foo/index.json'},
            {path => '/timelines/'},
            {path => '/timelines'},
        ) {
            $tester->request_ok('GET', $case->{path}, undef, qr/^404$/, "$case->{path}: not found OK");
        }
    };
}

done_testing();

