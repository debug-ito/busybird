use strict;
use warnings;
use Test::More;
use Test::Exception;
use File::HomeDir::Test;
use File::HomeDir;
use File::Spec;

BEGIN {
    use_ok("BusyBird::Runner");
}

my $EXP_CONFIG_DIR = File::Spec->catdir(File::HomeDir->my_home, ".busybird");
my $EXP_DEFAULT_CONFIG = File::Spec->catfile($EXP_CONFIG_DIR, "config.psgi");

{
    note("-- no args");
    my @opts = BusyBird::Runner::prepare_plack_opts();
    is scalar(grep { $_ eq $EXP_DEFAULT_CONFIG } @opts), 1, "generate plack opts with config filename";
    ok(-d $EXP_CONFIG_DIR, "config directory '$EXP_CONFIG_DIR' generated");
    ok(-f $EXP_DEFAULT_CONFIG, "default config file '$EXP_DEFAULT_CONFIG' generated");
    open my $file, "<", $EXP_DEFAULT_CONFIG or die "Cannot read $EXP_DEFAULT_CONFIG: $!";
    my $default_config = do { local $/; <$file> };
    close $file;
    like $default_config, qr/use BusyBird;/, "default config OK";
    unlink $EXP_DEFAULT_CONFIG;
}

{
    note("-- explicit config file: existing");
    my @opts = BusyBird::Runner::prepare_plack_opts("xt/Runner.t");
    is scalar(grep { $_ eq "xt/Runner.t" } @opts), 1, "generate plack opts with config filename";
}

{
    note("-- explicit config file: non-existent");
    my @warns = ();
    local $SIG{__WARN__} = sub { push @warns, shift };
    dies_ok { BusyBird::Runner::prepare_plack_opts("xt/hogehoge") } "passing explicit non-existent config file leads to death";
    note("Reported warnings:");
    note(join "", @warns);
}

{
    note("-- --help option");
    my @warns = ();
    local $SIG{__WARN__} = sub { push @warns, shift };
    dies_ok { BusyBird::Runner::prepare_plack_opts("--help", "xt/Runner.t") } "--help option raises exception";
    is scalar(@warns), 0, "no warnings";
}

done_testing;
