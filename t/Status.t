use strict;
use warnings;
use Test::More;
use BusyBird::Log;
use Storable qw(dclone);
use FindBin;
use lib "$FindBin::RealBin/lib";
use BusyBird::Test::StatusHTML;

note('--- test of status rendering');

BEGIN {
    use_ok("BusyBird::Main");
    use_ok("BusyBird::Main::PSGI::View");
    use_ok("BusyBird::StatusStorage::Memory");
}

$BusyBird::Log::Logger = undef;

sub create_renderer {
    my $main = BusyBird::Main->new;
    $main->set_config(default_status_storage => BusyBird::StatusStorage::Memory->new());
    $main->timeline("home");
    return BusyBird::Main::PSGI::View->new(main_obj => $main);
}

sub render_status {
    my ($renderer, $status) = @_;
    my $html = $renderer->_format_status_html_destructive(dclone $status);
    return BusyBird::Test::StatusHTML->new(html => $html);
}

{
    note("------- Status ID rendering tests");
    my $ren = create_renderer();
    foreach my $case (
        {in_id => 'http://example.com/', exp_id => 'http://example.com/'},
        {in_id => 'crazy<>ID', exp_id => 'crazy&lt;&gt;ID'},
        {in_id => 'crazier<span>ID</span>', exp_id => 'crazier&lt;span&gt;ID&lt;/span&gt;'},
        {in_id => 'ID with space', exp_id => 'ID with space'},
    ) {
        my $in_status = { id => $case->{in_id} };
        my $out_status = render_status($ren, $in_status);
        ## diag($out_status->raw_html);
        is($out_status->id, $case->{exp_id}, "In ID: $case->{in_id} OK");
    }
}

done_testing();

