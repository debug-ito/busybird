use strict;
use warnings;
use Test::More;
use DateTime;
use BusyBird::DateTime::Format;

BEGIN {
    use_ok('BusyBird::Input::Generator');
}

sub test_uniqueness {
    my ($statuses_ref) = @_;
    my @all_statuses = map { @$_ } values %$statuses_ref;
    my %id_dict = map { $_->{id} => 1 } @all_statuses;
    is(scalar(keys %id_dict), scalar(@all_statuses), "IDs are all unique");
}

{
    my %generators = (
        empty => new_ok('BusyBird::Input::Generator'),
        hoge  => new_ok('BusyBird::Input::Generator', [screen_name => "hoge"]),
    );
    my %statuses = (
        empty => [],
        hoge  => [],
    );

    foreach my $i (0..10) {
        foreach my $key (keys %generators) {
            push(@{$statuses{$key}}, $generators{$key}->generate(text => $i, level => $i));
        }
    }

    test_uniqueness(\%statuses);

    foreach my $i (0..10) {
        foreach my $type (keys %statuses) {
            is($statuses{$type}[$i]{text}, $i, "'$type' status $i text OK");
            is($statuses{$type}[$i]{busybird}{level}, $i, "'$type' status $i level OK");
            isa_ok(BusyBird::DateTime::Format->parse_datetime($statuses{$type}[$i]{created_at}), "DateTime",
                   "'$type' status $i created_at OK");
        }
        is($statuses{empty}[$i]{user}{screen_name}, "", "'empty' status $i screen_name OK ");
        is($statuses{hoge}[$i]{user}{screen_name}, "hoge", "'hoge' status $i screen_name OK");
    }

    {
        my $no_level_status = $generators{hoge}->generate(text => "no level");
        is($no_level_status->{busybird}{level}, 0, "if level param is omitted, busybird.level == 0.");
    }
}

{
    note("--- generate_id() tests");
    my $gen = BusyBird::Input::Generator->new(screen_name => "hoge");
    my @ids = ();
    my $hoge_id = $gen->generate_id();
    like($hoge_id, qr/hoge/, "hoge_id includes hoge");
    push(@ids, $hoge_id);
    my $foobar_id = $gen->generate_id("foobar");
    like($foobar_id, qr/foobar/, "foobar_id includes foobar");
    unlike($foobar_id, qr/hoge/, "... and does not include hoge");
    push(@ids, $foobar_id);

    my $future_date = DateTime->now;
    $future_date->add(days => 10);
    foreach (1..10) {
        push(@ids, $gen->generate_id(undef, $future_date));
    }

    my %ids_dict = map { $_ => 1 } @ids;
    is(int(@ids), int(keys(%ids_dict)), "IDs are all unique");
}

done_testing();
