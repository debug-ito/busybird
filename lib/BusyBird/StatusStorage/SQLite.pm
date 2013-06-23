package BusyBird::StatusStorage::SQLite;
use strict;
use warnings;
use base ("BusyBird::StatusStorage");
use BusyBird::Version;
our $VERSION = $BusyBird::Version::VERSION;
use DBI;
use Carp;
use Try::Tiny;
use SQL::Maker;
use BusyBird::DateTime::Format;
use JSON;
no autovivification;

my $UNDEF_TIMESTAMP = '9999-99-99T99:99:99';

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        dbi_source => undef,
        maker => SQL::Maker->new(driver => 'SQLite'),
    }, $class;
    croak "path parameter is mandatory" if not defined $args{path};
    $self->{dbi_source} = "dbi:SQLite:dbname=$args{path}";
    $self->_create_tables();
    return $self;
}

sub _get_dbh {
    my ($self, $dbi_source, $dbi_username, $dbi_password, $attr) = @_;
    return DBI->connect($dbi_source, $dbi_username, $dbi_password, $attr);
}

sub _get_my_dbh {
    my ($self) = @_;
    return $self->_get_dbh($self->{dbi_source}, "", "", {
        RaiseError => 1, PrintError => 0, AutoCommit => 1
    });
}

sub _create_tables {
    my ($self) = @_;
    my $dbh = $self->_get_my_dbh();
    $dbh->do(<<EOD);
CREATE TABLE IF NOT EXISTS statuses (
  id TEXT PRIMARY KEY UNIQUE NOT NULL,
  timeline_id INTEGER NOT NULL,
  level INTEGER NOT NULL,
  utc_acked_at TEXT NOT NULL,
  utc_created_at TEXT NOT NULL,
  timezone_acked_at TEXT NOT NULL,
  timezone_created_at TEXT NOT NULL,
  content TEXT NOT NULL
)
EOD
    $dbh->do(<<EOD);
CREATE TABLE IF NOT EXISTS timelines (
  id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
  name TEXT UNIQUE NOT NULL,
)
EOD
}

sub put_statuses {
    my ($self, %args) = @_;
    my $timeline = $args{timeline};
    croak "timeline parameter is mandatory" if not defined $timeline;
    my $mode = $args{mode};
    croak "mode parameter is mandatory" if not defined $mode;
    if($mode ne 'insert' && $mode ne 'update' && $mode ne 'upsert') {
        croak "mode must be either insert, update or upsert";
    }
    my $statuses = $args{statuses};
    croak "statuses parameter is mandatory" if not defined $statuses;
    if(ref($statuses) ne 'HASH' && ref($statuses) ne 'ARRAY') {
        croak "statuses parameter must be either a status object or an array-ref of statuses";
    }
    if(ref($statuses) eq 'HASH') {
        $statuses = [$statuses];
    }
    my $callback = $args{callback} || sub {};
    my $dbh;
    try {
        $dbh = $self->_get_my_dbh();
        $dbh->begin_work();
        my $timeline_id = $self->_get_timeline_id($dbh, $timeline);
        my $sth;
        my $total_count = 0;
        foreach my $status (@$statuses) {
            my $record = _to_status_record($timeline_id, $status);
            if($mode eq 'update') {
                my ($sql, @bind) = $self->{maker}->update('statuses', $record, [
                    'timeline_id' => $timeline_id, id => $status->{id}
                ]);
                if(!$sth) {
                    $sth = $dbh->prepare($sql);
                }
                my $count = $sth->execute(@bind);
                if($count > 0) {
                    $total_count += $count;
                }
            }elsif($mode eq 'insert') {
                
            }else {
                ## upsert
                
            }
        }
        $dbh->commit();
    } catch {
        my $e = shift;
        if($dbh) {
            $dbh->rollback();
        }
        $callback->($e);
    };
}

sub _get_timeline_id {
    my ($self, $dbh, $timeline_name) = @_;
    my ($sql, @bind) = $self->{maker}->select('timelines', ['id'], ['name' => $timeline_name]);
    my $record = $dbh->selectrow_arrayref($sql, undef, @bind);
    if(!defined($record)) {
        croak "No timeline named '$timeline_name'";
    }
    return $record->[0];
}

sub _to_status_record {
    my ($timeline_id, $status) = @_;
    croak "status ID must be set" if not defined $status->{id};
    croak "timeline_id must be defined" if not defined $timeline_id;
    my $record = {
        id => $status->{id},
        timeline_id => $timeline_id,
        level => $status->{busybird}{level} || 0,
    };
    ($record->{utc_acked_at}, $record->{timezone_acked_at}) = _extract_utc_timestamp_and_timezone($status->{busybird}{acked_at});
    ($record->{utc_created_at}, $record->{timezone_created_at}) = _extract_utc_timestamp_and_timezone($status->{created_at});
    $record->{content} = encode_json($status);
    return $record;
}

sub _extract_utc_timestamp_and_timezone {
    my ($timestamp_str) = @_;
    if(!defined($timestamp_str) || $timestamp_str eq '') {
        return ($UNDEF_TIMESTAMP, 'UTC');
    }
    my $datetime = BusyBird::DateTime::Format->parse_datetime($timestamp_str);
    croak "Invalid datetime format: $timestamp_str" if not defined $datetime;
    my $timezone_name = $datetime->time_zone->name;
    $datetime->set_time_zone('UTC');
    my $utc_timestamp = $datetime->strftime('%Y-%m-%dT%H:%M:%S');
    return ($utc_timestamp, $timezone_name);
}

1;

__END__

=pod

=head1 NAME

BusyBird::StatusStorage::SQLite - status storage in SQLite database

=head1 SYNOPSIS

    write synopsis!!

=head1 DESCRIPTION

This is an implementation of L<BusyBird::StatusStorage> interface.
It stores statuses in an SQLite database.

This storage is synchronous, i.e., all operations block the thread.

=head1 CLASS METHOD

=head2 $storage = BusyBird::StatusStorage::SQLite->new(%args)

The constructor.

Fields in C<%args> are:

=over

=item C<path> => FILE_PATH (mandatory)

Path string to the SQLite database file.
If C<":memory:"> is given to this parameter, a temporary in-memory database is created.

=item C<max_status_num> => INT (optional, default: 4000)

The maximum number of statuses the storage can store per timeline.
You cannot expect a timeline to keep more statuses than this number.

=item C<hard_max_status_num> => INT (optional, default: 120% of max_status_num)

The hard limit max number of statuses per timeline.
When the number of statuses in a timeline exceeds this number,
it deletes old statuses from the timeline so that the timeline has C<max_status_num> statuses.

=item C<vacuum_on_delete> => INT (optional, default: 1600)

The status storage automatically executes C<vacuum()> every time this number of statuses are
deleted from the storage. The number is for the whole storage, not per timeline.

If you set this option less than or equal to 0, it never C<vacuum()> itself.


=back

=head1 OBJECT METHODS

L<BusyBird::StatusStorage::SQLite> implements all object methods in L<BusyBird::StatusStorage>.
In addition to it, it has the following methods.

=head2 $storage->vacuum()

Executes SQL C<VACUUM> on the database.


=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut

