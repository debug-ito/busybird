use strict;
use warnings;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use Getopt::Long qw(:config bundling no_ignore_case);
use Pod::Usage;
use Try::Tiny;
use JSON;
use DBI;
use BusyBird::StatusStorage::SQLite;
use BusyBird::Timeline;
use BusyBirdBenchmark::StatusStorage;
use Timer::Simple;
use Storable qw(dclone);


sub get_delete_count {
    my ($db_filename) = @_;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$db_filename", "","", {
        RaiseError => 1, PrintError => 0, AutoCommit => 1
    });
    my $record = $dbh->selectrow_arrayref(
        "SELECT delete_count FROM delete_counts WHERE delete_count_id = ?",
        undef, 0
    );
    die "cannot fetch delete count" if not defined $record;
    return $record->[0];
}

my $AUTO_REMOVE = 0;
my $TIMELINE_NUM = 1;
my $STATUS_COUNT_ONE_TIME = 200;
my $PUT_NUM = 40;
my $STORAGE_FILENAME;

try {
    GetOptions(
        'R' => \$AUTO_REMOVE,
        't=i' => \$TIMELINE_NUM,
        'c=i' => \$STATUS_COUNT_ONE_TIME,
        'N=i' => \$PUT_NUM,
    );
    $STORAGE_FILENAME = $ARGV[0];
    die "No STORAGE_FILENAME specified.\n" if not defined $STORAGE_FILENAME;
}catch {
    my $e = shift;
    warn "$e\n";
    pod2usage(-verbose => 2, -noperldoc => 1);
    exit 0;
};

if(-r $STORAGE_FILENAME) {
    if(!$AUTO_REMOVE) {
        die "$STORAGE_FILENAME already exists. Remove that manually or use -R option.\n";
    }
    unlink($STORAGE_FILENAME) or die "cannot remove $STORAGE_FILENAME";
    print STDERR "$STORAGE_FILENAME is removed.\n";
}

my $storage = BusyBird::StatusStorage::SQLite->new(
    path => $STORAGE_FILENAME,
    vacuum_on_delete => 0,
);

my @timelines = map { BusyBird::Timeline->new(name => "timeline_$_", storage => $storage) } 1..$TIMELINE_NUM;

my @statuses = (map { dclone($BusyBirdBenchmark::StatusStorage::SAMPLE_STATUS) } 1..$STATUS_COUNT_ONE_TIME);

my $timer = Timer::Simple->new;
print STDERR "Start putting: ";
foreach my $round (1 .. $PUT_NUM) {
    foreach my $timeline (@timelines) {
        $timeline->add(\@statuses, sub {
            my ($error, $num) = @_;
            die "put error: $error" if defined($error);
            if($num != $STATUS_COUNT_ONE_TIME) {
                die("Timeline " . $timeline->name . ": $num (!= $STATUS_COUNT_ONE_TIME) inserted. something is wrong.");
            }
        });
    }
    print STDERR ".";
}
print STDERR "\n";
print STDERR "Put completes in $timer\n";

foreach my $timeline (@timelines) {
    $timeline->get_unacked_counts(callback => sub {
        my ($error, $unacked_counts) = @_;
        die "get unacked counts error: $error" if defined $error;
        print STDERR "Timeline ", $timeline->name, ": ", $unacked_counts->{total}, " unacked statuses\n";
    });
}

print STDERR "Do vacuum\n";
$timer = Timer::Simple->new;
$storage->vacuum();
print STDERR "Vacuum completes in $timer\n";

__END__

=pod

=head1 NAME

vacuum_time.pl - Measure how long BusyBird::StatusStorage::SQLite::vacuum() takes

=head1 SYNOPSIS

    $ perl vacuum_time.pl [OPTIONS] SQLITE_FILENAME

=head1 DESCRIPTION

SQLITE_FILENAME is the SQLite database filename for the test.
It first populates some statuses into the storage, then it calls vacuum() and measures its time.

=head1 OPTIONS

=over

=item -R

Optional. If set, the file SQLITE_FILENAME is removed before the test.
Otherwise, it aborts the script if SQLITE_FILENAME already exists.

=item -t TIMELINE_NUM

Optional (default: 1). The number of timelines it will create in the storage.

=item -c STATUS_COUNT_ONE_TIME

Optional (default: 200).
The number of statuses inserted into each timeline for a single call of put_statuses() method.

=item -N PUT_NUM

Optional (default: 40).
The number of calls of put_statuses() method for each timeline.
Thus, (STATUS_COUNT_ONE_TIME * PUT_NUM) statuses will be inserted into each timeline before vacuum().

=back

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut
