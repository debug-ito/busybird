=pod

=head1 NAME

profile_sqlite.pl - Do profiling on StatusStorage::SQLite storage

=head1 SYNOPSIS

    $ perl -d:NYTProf profile_sqlite.pl
    $ nytprofhtml

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut

use strict;
use warnings;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use BusyBird::StatusStorage::SQLite;
use BusyBird::Timeline;
use BusyBirdBenchmark::StatusStorage;
use Storable qw(dclone);

my $DB_FILENAME = "profile_sqlite.sqlite3";
if(-r $DB_FILENAME) {
    die "$DB_FILENAME already exists.\n";
}

my $storage = BusyBird::StatusStorage::SQLite->new(
    path => $DB_FILENAME, vacuum_on_delete => 0
);
my $timeline = BusyBird::Timeline->new(
    name => "test", storage => $storage
);

my @inserted_statuses = map { dclone($BusyBirdBenchmark::StatusStorage::SAMPLE_STATUS) } 1..200;

foreach (1..10) {
    $timeline->add(\@inserted_statuses, sub {
        my ($e, $num) = @_;
        die "$e" if defined $e;
        die "add num $num != 200" if $num != 200;
    });
}

my @ids = ();
$timeline->get_statuses(ack_state => 'unacked', count => 200, callback => sub {
    my ($e, $statuses) = @_;
    die "$e" if defined $e;
    my $num = scalar(@$statuses);
    die "status num $num != 200" if $num != 200;
    @ids = map { $_->{id} } @$statuses;
});

$timeline->ack_statuses(ids => \@ids);

