=pod

=head1 NAME

storages.pl - Benchmark StatusStorage::SQLite storages

=head1 SYNOPSIS

    $ perl storages.pl > result.plot

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut


package BusyBird::StatusStorage::SQLite::NaiveConnectionCache;
use strict;
use warnings;
use parent ('BusyBird::StatusStorage::SQLite');

sub _get_my_dbh {
    my ($self) = @_;
    if(!$self->{naive_connection_cache}) {
        $self->{naive_connection_cache} = $self->SUPER::_get_my_dbh();
    }
    return $self->{naive_connection_cache};
}

package main;
use strict;
use warnings;
use FindBin;
use lib ("$FindBin::RealBin/lib");
use BusyBirdBenchmark::StatusStorage;
use BusyBird::StatusStorage::SQLite;

my @DB_FILENAMES = qw(benchmark.file.sqlite3 benchmark.conn_cache.sqlite3);

foreach my $file (@DB_FILENAMES) {
    if(-r $file) {
        die "$file already exists.\n";
    }
}

BusyBirdBenchmark::StatusStorage->benchmark({
    run_count => 200,
}, {
    memory    => BusyBird::StatusStorage::SQLite->new(path => ':memory:', vacuum_on_delete => 0),
    file      => BusyBird::StatusStorage::SQLite->new(path => $DB_FILENAMES[0], vacuum_on_delete => 0),
    conncache => BusyBird::StatusStorage::SQLite::NaiveConnectionCache->new(path => $DB_FILENAMES[1], vacuum_on_delete => 0),
});



