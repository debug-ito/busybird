=pod

=head1 NAME

ack_trend.pl - output trend plot of ack time

=head1 SYNOPSIS

    $ perl ack_trend.pl > result.plot

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut

use strict;
use warnings;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use BusyBirdBenchmark::StatusStorage;
use BusyBird::StatusStorage::SQLite;

my $db_filename = "ack_trend.sqlite3";

die "$db_filename already exists" if -r $db_filename;

my $storage = BusyBird::StatusStorage::SQLite->new(path => $db_filename, vacuum_on_delete => 0);

print STDERR "Initializing...\n";
my $bench = BusyBirdBenchmark::StatusStorage->new(
    storage => $storage
);
print STDERR "Done\n";

foreach (1..200) {
    print STDERR "*";
    my $ret = $bench->run_once();
    printf("%e\n", $ret->{ack});
}
print STDERR "\n";

