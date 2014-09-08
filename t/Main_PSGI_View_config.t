use strict;
use warnings;
use Test::More;
use BusyBird::Main;
use BusyBird::StatusStorage::SQLite;
use BusyBird::Main::PSGI::View;
use lib "t";
use testlib::Main_Util qw(create_main);
use testlib::HTTP;

sub get_tree {
    my ($psgi_response) = @_;
    return testlib::HTTP->parse_html(@{$psgi_response->[2]});
}

sub get_inline_style {
    my ($tree) = @_;
    return join "\n", map {
        $_->content_list
    } $tree->findnodes('//style');
}

note("Tests of View related to configuration parameters");

{
    my $main = create_main();
    $main->timeline("test")->set_config(
        post_button_url => 'http://hoge.com/post',
        attached_image_max_height => 256,
    );
    my $view = BusyBird::Main::PSGI::View->new(main_obj => $main);
    my $tree = get_tree($view->response_timeline("test", ""));
    
    cmp_ok $tree->findnodes('//a[@href="http://hoge.com/post"]')->size, ">", 0, "at least one post_button_url link";

    my $got_style = get_inline_style($tree);
    like $got_style, qr|bb-status-extension-pane\s*\{\s*display\s*:\s*none|, "extension pane is hidden by default";
    like $got_style, qr|bb-status-extension-collapser\s*\{\s*display\s*:\s*none|, "... collapser is hidden";
}

{
    my $main = create_main();
    $main->timeline("test")->set_config(
        attached_image_show_default => "visible"
    );
    my $view = BusyBird::Main::PSGI::View->new(main_obj => $main);
    my $tree = get_tree($view->response_timeline("test", ""));
    my $got_style = get_inline_style($tree);
    like $got_style, qr|bb-status-extension-pane\s*\{\s*display\s*:\s*block|, "extension pane is visible by default";
    like $got_style, qr|bb-status-extension-expander\s*\{\s*display\s*:\s*none|, "... expander is hidden";
}

done_testing;

