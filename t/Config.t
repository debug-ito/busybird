use strict;
use warnings;
use Test::More;
use BusyBird::Main;
use BusyBird::Timeline;
use BusyBird::StatusStorage::Memory;
use BusyBird::Log;

$BusyBird::Log::Logger = undef;

sub create_main_and_timeline {
    my $main = BusyBird::Main->new();
    my $timeline = BusyBird::Timeline->new(
        name => "test",
        storage => BusyBird::StatusStorage::Memory->new()
    );
    $main->install_timeline($timeline);
    return ($main, $timeline);
}


{
    my ($main, $timeline) = create_main_and_timeline();
    note("--- basic config");
    foreach my $case (
        {label => "Main", target => $main},
        {label => "Timeline", target => $timeline}
    ) {
        is($case->{target}->get_config("_this_does_not_exist"), undef, "$case->{label}: get_config() for non-existent item returns undef");
        $case->{target}->set_config("__1" => 1, "__2" => 2);
        is($case->{target}->get_config("__1"), 1, "$case->{label}: set_config() param 1 OK");
        is($case->{target}->get_config("__2"), 2, "$case->{label}: set_config() param 2 OK");
    }
}

{
    note("--- config precedence for _get_timeline_config() method");
    my ($main, $timeline) = create_main_and_timeline();
    $main->set_config("_some_item" => "hoge");
    is($main->get_config("_some_item"), "hoge", "main gives hoge");
    is($timeline->get_config("_some_item"), undef, "timeline gives undef");
    is($main->get_timeline_config("test", "_some_item"), "hoge", "timeline_config gives hoge");
    $timeline->set_config("_some_item", "foobar");
    is($main->get_config("_some_item"), "hoge", "main gives hoge even after timeline config is set");
    is($timeline->get_config("_some_item"), "foobar", "timeline gives foobar after timeline config is set");
    is($main->get_timeline_config("test", "_some_item"), "foobar", "timeline_config gives foobar");
    is($main->get_timeline_config("__no_timeline", "_some_item"), "hoge", "timeline_config for non-existent timeline gives main's config");
    is($main->get_timeline_config("test", "no_item"), undef, "timeline_config for item not existing in either timeline or main gives undef");
}

{
    note("--- default config (_item_for_test)");
    my ($main, $timeline) = create_main_and_timeline();
    is($main->get_config("_item_for_test"), 1, "_item_for_test is 1 by default");
    is($main->get_config("time_zone"), "local", "default timezone OK");
    is($main->get_config("time_format"), '%x (%a) %X %Z', "default time_format OK");
    is($main->get_config("time_locale"), $ENV{LC_TIME} || "C", "default time_locale OK");
    is($main->get_config("post_button_url"), "https://twitter.com/intent/tweet", "default post_button_url OK");
}

done_testing();
