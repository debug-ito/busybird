=pod

=head1 NAME

profile_sqlite.pl - Do profiling on StatusStorage::SQLite storage

=head1 SYNOPSIS

    $ perl profile_sqlite.pl
    Begin populating profile_sqlite.sqlite3...
    Ack
    Done
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
my $INSERT_STATUS_NUM = 20;
my $INIT_INSERT_NUM = 300;
my $profiling_mode = (-r $DB_FILENAME);

my $storage = BusyBird::StatusStorage::SQLite->new(
    path => $DB_FILENAME, vacuum_on_delete => 0
);
my $timeline = BusyBird::Timeline->new(
    name => "test", storage => $storage
);

my @inserted_statuses = map { dclone($BusyBirdBenchmark::StatusStorage::SAMPLE_STATUS) } 1..$INSERT_STATUS_NUM;
my $add_callback = sub {
    my ($e, $num) = @_;
    die "$e" if defined $e;
    die "add num $num != $INSERT_STATUS_NUM" if $num != $INSERT_STATUS_NUM;
};

if(!$profiling_mode) {
    print STDERR "Begin populating $DB_FILENAME...\n";
    foreach (1..$INIT_INSERT_NUM) {
        $timeline->add(\@inserted_statuses, $add_callback);
    }
    print STDERR "Ack\n";
    $timeline->ack_statuses();
    print STDERR "Done\n";
    exit 0;
}


$timeline->add(\@inserted_statuses, $add_callback);

my @ids = ();
$timeline->get_statuses(ack_state => 'unacked', count => $INSERT_STATUS_NUM, callback => sub {
    my ($e, $statuses) = @_;
    die "$e" if defined $e;
    my $num = scalar(@$statuses);
    die "status num $num != $INSERT_STATUS_NUM" if $num != $INSERT_STATUS_NUM;
    @ids = map { $_->{id} } @$statuses;
});

$timeline->ack_statuses(ids => \@ids);
