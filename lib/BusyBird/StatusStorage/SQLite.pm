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
use Scalar::Util qw(looks_like_number);
use DateTime::Format::Strptime;
use DateTime;
no autovivification;

my $UNDEF_TIMESTAMP = '9999-99-99T99:99:99';
my $TIMESTAMP_FORMAT = DateTime::Format::Strptime->new(
    pattern => '%Y-%m-%dT:%H:%M:%S',
    time_zone => 'UTC',
    on_error => 'croak',
);

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        dbi_source => undef,
        maker => SQL::Maker->new(driver => 'SQLite'),
    }, $class;
    croak "path parameter is mandatory" if not defined $args{path};
    croak "in-memory database (:memory:) is not supported" if $args{path} eq ':memory:';
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
  timeline_id INTEGER NOT NULL,
  id TEXT NOT NULL,
  utc_acked_at TEXT NOT NULL,
  utc_created_at TEXT NOT NULL,
  timezone_acked_at TEXT NOT NULL,
  timezone_created_at TEXT NOT NULL,
  level INTEGER NOT NULL,
  content TEXT NOT NULL,

  PRIMARY KEY (timeline_id, id)
)
EOD
    $dbh->do(<<EOD);
CREATE TABLE IF NOT EXISTS timelines (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE NOT NULL
)
EOD
}

sub _put_update {
    my ($self, $dbh, $record, $prev_sth) = @_;
    my $sth = $prev_sth;
    my ($sql, @bind) = $self->{maker}->update('statuses', $record, [
        'timeline_id' => "$record->{timeline_id}", id => "$record->{id}"
    ]);
    if(!$sth) {
        $sth = $dbh->prepare($sql);
    }
    return ($sth->execute(@bind), $sth);
}

sub _put_insert {
    my ($self, $dbh, $record, $prev_sth) = @_;
    my $sth = $prev_sth;
    my ($sql, @bind) = $self->{maker}->insert('statuses', $record, {prefix => 'INSERT OR IGNORE INTO'});
    if(!$sth) {
        $sth = $dbh->prepare($sql);
    }
    return ($sth->execute(@bind), $sth);
}

sub _put_upsert {
    my ($self, $dbh, $record) = @_;
    my ($count) = $self->_put_update($dbh, $record);
    if($count <= 0) {
        ($count) = $self->_put_insert($dbh, $record);
    }
    return ($count, undef);
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
    my @results = try {
        return (undef, 0) if @$statuses == 0;
        $dbh = $self->_get_my_dbh();
        $dbh->begin_work();
        my $timeline_id = $self->_get_timeline_id($dbh, $timeline) || $self->_create_timeline($dbh, $timeline);
        if(!defined($timeline_id)) {
            die "Internal error: could not create a timeline '$timeline' somehow.";
        }
        my $sth;
        my $total_count = 0;
        my $put_method = "_put_$mode";
        foreach my $status (@$statuses) {
            my $record = _to_status_record($timeline_id, $status);
            my $count;
            ($count, $sth) = $self->$put_method($dbh, $record, $sth);
            if($count > 0) {
                $total_count += $count;
            }
        }
        $dbh->commit();
        return (undef, $total_count);
    } catch {
        my $e = shift;
        if($dbh) {
            $dbh->rollback();
        }
        return ($e);
    };
    @_ = @results;
    goto $callback;
}

sub _get_timeline_id {
    my ($self, $dbh, $timeline_name) = @_;
    my ($sql, @bind) = $self->{maker}->select('timelines', ['id'], ['name' => "$timeline_name"]);
    my $record = $dbh->selectrow_arrayref($sql, undef, @bind);
    if(!defined($record)) {
        return undef;
    }
    return $record->[0];
}

sub _create_timeline {
    my ($self, $dbh, $timeline_name) = @_;
    my ($sql, @bind) = $self->{maker}->insert('timelines', {name => "$timeline_name"});
    $dbh->do($sql, undef, @bind);
    return $self->_get_timeline_id($dbh, $timeline_name);
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

sub _from_status_record {
    my ($record) = @_;
    my $status = decode_json($record->{content});
    $status->{id} = $record->{id};
    if($record->{level} != 0 || defined($status->{busybird}{level})) {
        $status->{busybird}{level} = $record->{level};
    }
    my $acked_at_str = _create_bb_timestamp_from_utc_timestamp_and_timezone($record->{utc_acked_at}, $record->{timezone_acked_at});
    if(defined($acked_at_str) || defined($status->{busybird}{acked_at})) {
        $status->{busybird}{acked_at} = $acked_at_str;
    }
    my $created_at_str = _create_bb_timestamp_from_utc_timestamp_and_timezone($record->{utc_created_at}, $record->{timezone_created_at});
    if(defined($created_at_str) || defined($status->{created_at})) {
        $status->{created_at} = $created_at_str;
    }
    return $status;
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
    my $utc_timestamp = $TIMESTAMP_FORMAT->format_datetime($datetime);
    return ($utc_timestamp, $timezone_name);
}

sub _create_bb_timestamp_from_utc_timestamp_and_timezone {
    my ($utc_timestamp_str, $timezone) = @_;
    if($utc_timestamp_str eq $UNDEF_TIMESTAMP) {
        return undef;
    }
    my $dt = $TIMESTAMP_FORMAT->parse_datetime($utc_timestamp_str);
    $dt->set_time_zone($timezone);
    return BusyBird::DateTime::Format->format_datetime($dt);
}

sub get_statuses {
    my ($self, %args) = @_;
    my $timeline = $args{timeline};
    croak "timeline parameter is mandatory" if not defined $timeline;
    my $callback = $args{callback};
    croak "callback parameter is mandatory" if not defined $callback;
    croak "callback parameter must be a CODEREF" if ref($callback) ne "CODE";
    my $ack_state = defined($args{ack_state}) ? $args{ack_state} : "all";
    if($ack_state ne "all" && $ack_state ne "unacked" && $ack_state ne "acked") {
        croak "ack_state parameter must be either 'all' or 'acked' or 'unacked'";
    }
    my $max_id = $args{max_id};
    my $count = defined($args{count}) ? $args{count} : 'all';
    if($count ne 'all' && !looks_like_number($count)) {
        croak "count parameter must be either 'all' or number";
    }
    my @results = try {
        my $dbh = $self->_get_my_dbh();
        my $timeline_id = $self->_get_timeline_id($dbh, $timeline);
        if(!defined($timeline_id)) {
            return (undef, []);
        }
        my $cond = $self->_create_base_condition($timeline_id, $ack_state);
        if(defined($max_id)) {
            my $max_id_cond = $self->_create_max_id_condition($dbh, $timeline_id, $max_id, $ack_state);
            if(!defined($max_id_cond)) {
                return (undef, []);
            }
            $cond = ($cond & $max_id_cond);
        }
        my %maker_opt = (order_by => ['utc_acked_at DESC', 'utc_created_at DESC', 'id DESC']);
        if($count ne 'all') {
            $maker_opt{limit} = $count;
        }
        my ($sql, @bind) = $self->{maker}->select("statuses", ['*'], $cond, \%maker_opt);
        my $sth = $dbh->prepare($sql);
        $sth->execute(@bind);
        my @statuses = ();
        while(my $record = $sth->fetchrow_hashref('NAME_lc')) {
            push(@statuses, _from_status_record($record));
        }
        return (undef, \@statuses);
    }catch {
        my $e = shift;
        return ($e);
    };
    @_ = @results;
    goto $callback;
}

sub _create_base_condition {
    my ($self, $timeline_id, $ack_state) = @_;
    $ack_state ||= 'all';
    my $cond = $self->{maker}->new_condition();
    $cond->add(timeline_id => $timeline_id);
    if($ack_state eq 'acked') {
        $cond->add('utc_acked_at', {'!=' => $UNDEF_TIMESTAMP});
    }elsif($ack_state eq 'unacked') {
        $cond->add('utc_acked_at' => $UNDEF_TIMESTAMP);
    }
    return $cond;
}

sub _get_timestamps_of {
    my ($self, $dbh, $timeline_id, $status_id, $ack_state) = @_;
    my $cond = $self->_create_base_condition($timeline_id, $ack_state);
    $cond->add(id => "$status_id");
    my ($sql, @bind) = $self->{maker}->select("statuses", ['utc_acked_at', 'utc_created_at'], $cond, {
        limit => 1
    });
    my $record = $dbh->selectrow_arrayref($sql, undef, @bind);
    if(!$record) {
        return ();
    }
    return ($record->[0], $record->[1]);
}

sub _create_max_id_condition {
    my ($self, $dbh, $timeline_id, $max_id, $ack_state) = @_;
    my ($max_acked_at, $max_created_at) = $self->_get_timestamps_of($dbh, $timeline_id, $max_id, $ack_state);
    if(!defined($max_acked_at) || !defined($max_created_at)) {
        return undef;
    }
    my $cond = $self->{maker}->new_condition();
    $cond->add_raw(q{utc_acked_at < ? OR ( utc_acked_at = ? AND ( utc_created_at < ? OR ( utc_created_at = ? AND id <= ?)))},
                   $max_acked_at x 2, $max_created_at x 2, "$max_id");
    return $cond;
}

sub ack_statuses {
    my ($self, %args) = @_;
    my $timeline = $args{timeline};
    croak "timeline parameter is mandatory" if not defined $timeline;
    my $callback = defined($args{callback}) ? $args{callback} : sub {};
    croak "callback parameter must be a CODEREF" if ref($callback) ne 'CODE';
    my $ids = $args{ids};
    if(defined($ids) && ref($ids) ne 'ARRAY' && ref($ids) ne 'HASH') {
        croak "ids parameter must be either undef, a status object or an array-ref of statuses";
    }
    if(defined($ids) && ref($ids) eq 'HASH') {
        $ids = [$ids];
    }
    my $max_id = $args{max_id};
    my $dbh;
    my @results = try {
        my $ack_utc_timestamp = $TIMESTAMP_FORMAT->format_datetime(DateTime->now(time_zone => 'UTC'));
        $dbh = $self->_get_my_dbh();
        $dbh->begin_work();
        my $timeline_id = $self->_get_timeline_id($dbh, $timeline);
        return (undef, 0) if not defined $timeline_id;
        my $total_count = 0;
        if(!defined($ids) && !defined($max_id)) {
            $total_count = $self->_ack_all($dbh, $timeline_id, $ack_utc_timestamp);
        }else {
            if(defined($max_id)) {
                my $max_id_count = $self->_ack_max_id($dbh, $timeline_id, $ack_utc_timestamp, $max_id);
                $total_count += $max_id_count if $max_id_count > 0;
            }
            if(defined($ids)) {
                my $ids_count = $self->_ack_ids($dbh, $timeline_id, $ack_utc_timestamp, $ids);
                $total_count += $ids_count if $ids_count > 0;
            }
        }
        $dbh->commit();
        $total_count = 0 if $total_count < 0;
        return (undef, $total_count);
    }catch {
        my $e = shift;
        if($dbh) {
            $dbh->rollback();
        }
        return ($e);
    };
    @_ = @results;
    goto $callback;
}

sub _ack_all {
    my ($self, $dbh, $timeline_id, $ack_utc_timestamp) = @_;
    my ($sql, @bind) = $self->{maker}->update(
        'statuses', {utc_acked_at => $ack_utc_timestamp},
        [timeline_id => $timeline_id, utc_acked_at => $UNDEF_TIMESTAMP]
    );
    return $dbh->do($sql, undef, @bind);
}

sub _ack_max_id {
    my ($self, $dbh, $timeline_id, $ack_utc_timestamp, $max_id) = @_;
    my $max_id_cond = $self->_create_max_id_condition($dbh, $timeline_id, $max_id, 'unacked');
    if(!defined($max_id_cond)) {
        return 0;
    }
    my $cond = $self->_create_base_condition($timeline_id, 'unacked');
    my ($sql, @bind) = $self->{maker}->update(
        'statuses', {utc_acked_at => $ack_utc_timestamp}, ($cond & $max_id_cond)
    );
    return $dbh->do($sql, undef, @bind);
}

sub _ack_ids {
    my ($self, $dbh, $timeline_id, $ack_utc_timestamp, $ids) = @_;
    if(@$ids == 0) {
        return 0;
    }
    my $total_count = 0;
    my $sth;
    foreach my $id (@$ids) {
        my $cond = $self->_create_base_condition($timeline_id, 'unacked');
        $cond->add(id => "$id");
        my ($sql, @bind) = $self->{maker}->update(
            'statuses', {utc_acked_at => $ack_utc_timestamp}, $cond
        );
        if(!$sth) {
            $sth = $dbh->prepare($sql);
        }
        my $count = $sth->execute(@bind);
        if($count > 0) {
            $total_count += $count;
        }
    }
    return $total_count;
}

sub delete_statuses {
    my ($self, %args) = @_;
    my $timeline = $args{timeline};
    croak 'timeline parameter is mandatory' if not defined $timeline;
    croak 'ids parameter is mandatory' if not exists $args{ids};
    my $ids = $args{ids};
    if(defined($ids) && ref($ids) && ref($ids) ne 'ARRAY') {
        croak 'ids parameter must be either undef, a status ID or array-ref of status IDs.';
    }
    if(defined($ids) && !ref($ids)) {
        $ids = [$ids];
    }
    my $callback = defined($args{callback}) ? $args{callback} : sub {};
    croak 'callback parameter must be a CODEREF' if ref($callback) ne 'CODE';
    my $dbh;
    my @results = try {
        my $dbh = $self->_get_my_dbh();
        $dbh->begin_work();
        my $timeline_id = $self->_get_timeline_id($dbh, $timeline);
        if(!defined($timeline_id)) {
            return (undef, 0);
        }
        my $total_count;
        if(defined($ids)) {
            $total_count = $self->_delete_ids($dbh, $timeline_id, $ids);
        }else {
            $total_count = $self->_delete_timeline($dbh, $timeline_id);
        }
        $dbh->commit();
        $total_count = 0 if $total_count < 0;
        return (undef, $total_count);
    }catch {
        my $e = shift;
        if($dbh) {
            $dbh->rollback();
        }
        return ($e);
    };
    @_ = @results;
    goto $callback;
}

sub _delele_timeline {
    my ($self, $dbh, $timeline_id) = @_;
    my ($sql, @bind) = $self->{maker}->delete('statuses', [
        timeline_id => $timeline_id
    ]);
    my $status_count = $dbh->do($sql, undef, @bind);
    ($sql, @bind) = $self->{maker}->delete('timelines', [
        id => $timeline_id
    ]);
    $dbh->do($sql, undef, @bind);
    return $status_count;
}

sub _delete_ids {
    my ($self, $dbh, $timeline_id, $ids) = @_;
    return 0 if @$ids == 0;
    my $sth;
    my $total_count = 0;
    foreach my $id (@$ids) {
        my ($sql, @bind) = $self->{maker}->delete('statuses', [
            timeline_id => $timeline_id, id => "$id"
        ]);
        if(!$sth) {
            $sth = $dbh->prepare($sql);
        }
        my $count = $sth->execute(@bind);
        if($count > 0) {
            $total_count += $count;
        }
    }
    return $total_count;
}

sub get_unacked_counts {
    my ($self, %args) = @_;
    my $timeline = $args{timeline};
    croak 'timeline parameter is mandatory' if not defined $timeline;
    my $callback = $args{callback};
    croak 'callback parameter is mandatory' if not defined $callback;
    croak 'callback parameter must be a CODEREF' if ref($callback) ne 'CODE';
    my @results = try {
        my $dbh = $self->_get_my_dbh();
        my $timeline_id = $self->_get_timeline_id($dbh, $timeline);
        my %result_obj = (total => 0);
        if(!defined($timeline_id)) {
            return (undef, \%result_obj);
        }
        my $cond = $self->_create_base_condition($timeline_id, 'unacked');
        my ($sql, @bind) = $self->{maker}->select('statuses', ['level', \'count(id)'], $cond, {
            group_by => 'level'
        });
        my $sth = $dbh->prepare($sql);
        $sth->execute(@bind);
        while(my $record = $sth->fetchrow_arrayref()) {
            $result_obj{total} += $record->[1];
            $result_obj{$record->[0]} = $record->[1];
        }
        return (undef, \%result_obj);
    }catch {
        my $e = shift;
        return ($e);
    };
    @_ = @results;
    goto $callback;
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
Currently, in-memory database is not supported.

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

