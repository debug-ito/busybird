use strict;
use warnings;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use Test::More;
use BusyBird::Main;
use BusyBird::Main::PSGI;
use BusyBird::Log;
use BusyBird::StatusStorage::SQLite;
use Plack::Test;
use BusyBird::Test::HTTP;

$BusyBird::Log::Logger = undef;

sub create_main {
    my $main = BusyBird::Main->new;
    $main->set_config(default_status_storage => BusyBird::StatusStorage::SQLite->new(path => ':memory:'));
    return $main;
}

sub get_title {
    my ($html_tree) = @_;
    my ($title_node) = $html_tree->findnodes('//title');
    my ($title_text) = $title_node->content_list;
    return $title_text;
}

note("----- static HTML view tests");

{
    my $main = create_main();
    $main->timeline('foo');
    $main->timeline('bar');
    test_psgi create_psgi_app($main), sub {
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
            like(get_title($tree), qr/$case->{exp_timeline}/, '... View title OK');
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

{
    my $main = create_main();
    note('--- weird timeline cases');
    foreach my $case (
        {name => 'myline.old', path => '/timelines/myline.old', title => qr/myline\.old/},
        {name => 'A & B', path => '/timelines/A+%26+B', title => qr/A \&amp\; B/ },
        {name => q{"that's weird"}, path => '/timelines/%22that%27s+weird%22', title => qr{\&quot;that(\'|\&apos;|\&\#39;)s weird\&quot;}},
        {name => '<><>', path => '/timelines/%3C%3E%3C%3E/', title => qr{&lt;&gt;&lt;&gt;}},

        #### The following won't work because HTTP::Message::PSGI::req_to_psgi automatically URI-unescapes %2F into /,
        #### so the router cannot extract the timeline name.
        ## {name => '/', path => '/timelines/%2F', title => qr{/}},
    ) {
        $main->timeline($case->{name});
        test_psgi create_psgi_app($main), sub {
            my $tester = BusyBird::Test::HTTP->new(requester => shift);
            my $tree = $tester->request_htmltree_ok('GET', $case->{path}, undef, qr/^200$/, "$case->{name}: GET OK");
            like(get_title($tree), $case->{title}, "$case->{name}: title OK");
            $main->uninstall_timeline($case->{name});
            $tester->request_ok('GET', $case->{path}, undef, qr/^404$/, "$case->{name}: uninstalled OK");
        };
    }
}

fail("TODO: timeline list view (page param and selection of timelines)");

done_testing();

