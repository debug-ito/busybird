package BusyBird::StatusStorage::Memory;
use strict;
use warnings;
use parent ('BusyBird::StatusStorage');
use BusyBird::Util qw(set_param sort_statuses);
use BusyBird::DateTime::Format;
use BusyBird::Log;
use DateTime;
use Storable qw(dclone);
use Carp;
use List::Util qw(min);
use JSON;
use Try::Tiny;
use CPS qw(kpar);
use CPS::Functional qw(kmap);
use BusyBird::Version;
our $VERSION = $BusyBird::Version::VERSION;

sub new {
    my ($class, %options) = @_;
    my $self = bless {
        timelines => {}, ## timelines should always be sorted.
    }, $class;
    $self->set_param(\%options, 'max_status_num', 2000);
    if($self->{max_status_num} <= 0) {
        croak "max_status_num option must be bigger than 0.";
    }
    return $self;
}

sub _log {
    my ($self, $level, $msg) = @_;
    bblog($level, $msg);
}

sub _index {
    my ($self, $timeline, $id) = @_;
    return -1 if not defined($self->{timelines}{$timeline});
    my $tl = $self->{timelines}{$timeline};
    my @ret = grep { $tl->[$_]{id} eq $id } 0..$#$tl;
    confess "multiple IDs in timeline $timeline." if int(@ret) >= 2;
    return int(@ret) == 0 ? -1 : $ret[0];
}

sub _acked {
    my ($self, $status) = @_;
    no autovivification;
    return $status->{busybird}{acked_at};
}

sub save {
    my ($self, $filepath) = @_;
    if(not defined($filepath)) {
        croak '$filepath is not specified.';
    }
    my $file;
    if(!open $file, ">", $filepath) {
        $self->_log("error", "Cannot open $filepath to write.");
        return 0;
    }
    my $success;
    try {
        print $file encode_json($self->{timelines});
        $success = 1;
    }catch {
        my $e = shift;
        $self->_log("error", "Error while saving: $e");
        $success = 0;
    };
    close $file;
    return $success;
}

sub load {
    my ($self, $filepath) = @_;
    if(not defined($filepath)) {
        croak '$filepath is not specified.';
    }
    my $file;
    if(!open $file, "<", $filepath) {
        $self->_log("notice", "Cannot open $filepath to read");
        return 0;
    }
    my $success;
    try {
        my $text = do { local $/; <$file> };
        $self->{timelines} = decode_json($text);
        $success = 1;
    }catch {
        my $e = shift;
        $self->_log("error", "Error while loading: $e");
        $success = 0;
    };
    close $file;
    return $success;
}

sub put_statuses {
    my ($self, %args) = @_;
    croak 'timeline arg is mandatory' if not defined $args{timeline};
    my $timeline = $args{timeline};
    if(!defined($args{mode}) ||
           ($args{mode} ne 'insert'
                && $args{mode} ne 'update' && $args{mode} ne 'upsert')) {
        croak 'mode arg must be insert/update/upsert';
    }
    my $mode = $args{mode};
    my $statuses;
    if(!defined($args{statuses})) {
        croak 'statuses arg is mandatory';
    }elsif(ref($args{statuses}) eq 'HASH') {
        $statuses = [ $args{statuses} ];
    }elsif(ref($args{statuses}) eq 'ARRAY') {
        $statuses = $args{statuses};
    }else {
        croak 'statuses arg must be STATUS/ARRAYREF_OF_STATUSES';
    }
    foreach my $s (@$statuses) {
        croak "{id} field is mandatory in statuses" if not defined $s->{id};
    }
    my $put_count = 0;
    foreach my $status_index (reverse 0 .. $#$statuses) {
        my $s = $statuses->[$status_index];
        my $tl_index = $self->_index($timeline, $s->{id});
        my $existent = ($tl_index >= 0);
        next if ($mode eq 'insert' && $existent) || ($mode eq 'update' && !$existent);
        my $is_insert = ($mode eq 'insert');
        if($mode eq 'upsert') {
            $is_insert = (!$existent);
        }
        if($is_insert) {
            unshift(@{$self->{timelines}{$timeline}}, dclone($s));
        }else {
            ## update
            $self->{timelines}{$timeline}[$tl_index] = dclone($s);
        }
        $put_count++;
    }
    if($put_count > 0) {
        $self->{timelines}{$timeline} = sort_statuses($self->{timelines}{$timeline});
        if(int(@{$self->{timelines}{$timeline}}) > $self->{max_status_num}) {
            splice(@{$self->{timelines}{$timeline}}, -(int(@{$self->{timelines}{$timeline}}) - $self->{max_status_num}));
        }
    }
    if($args{callback}) {
        @_ = (undef, $put_count);
        goto $args{callback};
    }
}

sub delete_statuses {
    my ($self, %args) = @_;
    croak 'timeline arg is mandatory' if not defined $args{timeline};
    croak 'ids arg is mandatory' if not exists $args{ids};
    my $timeline = $args{timeline};
    if(!$self->{timelines}{$timeline}) {
        if($args{callback}) {
            @_ = (undef, 0);
            goto $args{callback};
        }
        return;
    }
    my $ids = $args{ids};
    if(defined($ids)) {
        if(!ref($ids)) {
            $ids = [$ids];
        }elsif(ref($ids) eq 'ARRAY') {
            ;
        }else {
            croak "ids must be undef/ID/ARRAYREF_OF_IDS";
        }
    }
    my $delete_num = 0;
    if(defined($ids)) {
        foreach my $id (@$ids) {
            my $tl_index = $self->_index($timeline, $id);
            last if $tl_index < 0;
            splice(@{$self->{timelines}{$timeline}}, $tl_index, 1);
            $delete_num++;
        }
    }else {
        if(defined($self->{timelines}{$timeline})) {
            $delete_num = @{$self->{timelines}{$timeline}};
            delete $self->{timelines}{$timeline};
        }
    }
    if($args{callback}) {
        @_ = (undef, $delete_num);
        goto $args{callback};
    }
}

sub get_statuses {
    my ($self, %args) = @_;
    croak 'timeline arg is mandatory' if not defined $args{timeline};
    croak 'callback arg is mandatory' if not defined $args{callback};
    my $timeline = $args{timeline};
    if(!$self->{timelines}{$timeline}) {
        @_ = (undef, []);
        goto $args{callback};
    }
    my $ack_state = $args{ack_state} || 'any';
    my $max_id = $args{max_id};
    my $count = defined($args{count}) ? $args{count} : 20;
    my $ack_test = $ack_state eq 'unacked' ? sub {
        !$self->_acked(shift);
    } : $ack_state eq 'acked' ? sub {
        $self->_acked(shift);
    } : sub { 1 };
    my $start_index;
    if(defined($max_id)) {
        my $tl_index = $self->_index($timeline, $max_id);
        if($tl_index < 0) {
            @_ = (undef, []);
            goto $args{callback};
        }
        my $s = $self->{timelines}{$timeline}[$tl_index];
        if(!$ack_test->($s)) {
            @_ = (undef, []);
            goto $args{callback};
        }
        $start_index = $tl_index;
    }
    my @indice = grep {
        if(!$ack_test->($self->{timelines}{$timeline}[$_])) {
            0;
        }elsif(defined($start_index) && $_ < $start_index) {
            0;
        }else {
            1;
        }
    } 0 .. $#{$self->{timelines}{$timeline}};
    $count = int(@indice) if $count eq 'all';
    $count = min($count, int(@indice));
    my $result_statuses = $count <= 0 ? [] : [ map {
        dclone($self->{timelines}{$timeline}[$_])
    } @indice[0 .. ($count-1)] ];

    @_ = (undef, $result_statuses);
    goto $args{callback};
}

sub _get_unacked_statuses_by_ids {
    my ($self, $timeline, $ids, $callback) = @_;
    if(not defined $ids) {
        @_ = (undef, []);
        goto $callback;
    }
    kmap($ids, sub {
        my ($id, $done) = @_;
        try {
            $self->get_statuses(
                timeline => $timeline, max_id => $id, ack_state => 'unacked', count => 1,
                callback => sub {
                    my ($error, $statuses) = @_;
                    if(defined($error)) {
                        @_ = ({error => $error});
                        goto $done;
                    }elsif(defined($statuses->[0])) {
                        @_ = ({status => $statuses->[0]});
                        goto $done;
                    }else {
                        @_ = ();
                        goto $done;
                    }
                }
            );
        }catch {
            my $e = shift;
            @_ = ({error => $e});
            goto $done;
        };
    }, sub {
        my @results = @_;
        my @statuses = ();
        foreach my $result (@results) {
            if(defined $result->{error}) {
                @_ = ($result->{error});
                goto $callback;
            }
            if(not defined $result->{status}) {
                confess "undefined status in _get_unacked_statuses_by_ids.";
            }
            push(@statuses, $result->{status});
        }
        @_ = (undef, \@statuses);
        goto $callback;
    });
}

sub _uniq_statuses {
    my (@statuses) = @_;
    my %id_to_s = map { $_->{id} => $_ } @statuses;
    return values %id_to_s;
}

sub ack_statuses {
    my ($self, %args) = @_;
    croak 'timeline arg is mandatory' if not defined $args{timeline};
    my $ids;
    if(defined($args{ids})) {
        if(!ref($args{ids})) {
            $ids = [$args{ids}];
        }elsif(ref($args{ids}) eq 'ARRAY') {
            $ids = $args{ids};
        }else {
            croak "ids arg must be either undef, status ID or array-ref of IDs";
        }
    }
    my $max_id = $args{max_id};
    my $timeline = $args{timeline};
    my $callback = $args{callback} || sub {};
    if(!$self->{timelines}{$timeline}) {
        @_ = (undef, 0);
        goto $callback;
    }
    my $ack_str = BusyBird::DateTime::Format->format_datetime(
        DateTime->now(time_zone => 'UTC')
    );
    my @target_statuses = ();
    my $method_error;
    kpar sub {
        my $done = shift;
        $self->_get_unacked_statuses_by_ids($timeline, $ids, sub {
            my ($error, $statuses) = @_;
            if(defined $error) {
                $method_error = $error;
                goto $done;
            }
            push(@target_statuses, @$statuses);
            goto $done;
        });
    }, (defined($ids) && !defined($max_id) ? () : sub {
        my $done = shift;
        $self->get_statuses(
            timeline => $timeline,
            max_id => $max_id, count => 'all',
            ack_state => 'unacked',
            callback => sub {
                my ($error, $statuses) = @_;
                if(defined($error)) {
                    $method_error = "get error: $error";
                    goto $done;
                }
                push(@target_statuses, @$statuses);
                goto $done;
            }
        );
    }), sub {
        ## ** final function for kpar
        if(defined $method_error) {
            @_ = ($method_error);
            goto $callback;
        }
        @target_statuses = _uniq_statuses @target_statuses;
        if(!@target_statuses) {
            @_ = (undef, 0);
            goto $callback;
        }
        $_->{busybird}{acked_at} = $ack_str foreach @target_statuses;
        $self->put_statuses(
            timeline => $timeline, mode => 'update',
            statuses => \@target_statuses, callback => sub {
                my ($error, $changed) = @_;
                if(defined($error)) {
                    @_ = ("put error: $error");
                    goto $callback;
                }
                @_ = (undef, $changed);
                goto $callback;
            }
        );
    };
}

sub get_unacked_counts {
    my ($self, %args) = @_;
    croak 'timeline arg is mandatory' if not defined $args{timeline};
    croak 'callback arg is mandatory' if not defined $args{callback};
    my $timeline = $args{timeline};
    if(!$self->{timelines}{$timeline}) {
        @_ = (undef, {total => 0});
        goto $args{callback};
    }
    my @statuses = grep {
        !$self->_acked($_)
    } @{$self->{timelines}{$timeline}};
    my %count = (total => int(@statuses));
    foreach my $status (@statuses) {
        my $level = do {
            no autovivification;
            $status->{busybird}{level} || 0;
        };
        $count{$level}++;
    }
    @_ = (undef, \%count);
    goto $args{callback};
}

1;

__END__

=pod

=head1 NAME

BusyBird::StatusStorage::Memory - Simple status storage in the process memory

=head1 SYNOPSIS

    use BusyBird::StatusStorage::Memory;
    
    ## The statuses are stored in the process memory.
    my $storage = BusyBird::StatusStorage::Memory->new();

    ## Load statuses from a file
    $storage->load("my_statuses.json");
    
    ## Save the content of the storage into a file
    $storage->save("my_statuses.json");


=head1 DESCRIPTION

This module is an implementation of L<BusyBird::StatusStorage>.

This storage stores all statuses in the process memory.
The stored statuses can be saved to a file in JSON format.
The saved statuses can be loaded from the file.

This storage is rather for testing purposes.
If you want a light-weight in-memory status storage,
I recommend L<BusyBird::StatusStorage::SQLite>.

This storage is synchronous, i.e., all operations block the thread.

This module uses L<BusyBird::Log> for logging.

=head1 CAVEATS

=over

=item *

Because this storage stores statuses in the process memory,
forked servers cannot share the storage.

=item *

Because this storage stores statuses in the process memory,
the stored statuses are lost when the process is terminated.

=back

=head1 CLASS METHODS

=head2 $storage = BusyBird::StatusStorage::Memory->new(%options)

Creates the storage object.

You can specify the folowing options in C<%options>.

=over

=item C<max_status_num> => MAX_STATUS_NUM (optional, default: 2000)

Specifies the maximum number of statuses the storage can store per timeline.
If more statuses are added to a full timeline, the oldest statuses in the timeline are removed automatically.

=back

=head1 OBJECTS METHODS

In addition to the following methods,
all methods described in L<BusyBird::StatusStorage> are supported, too.


=head2 $is_success = $storage->save($filepath)

Saves the current content of the storage to the file named C<$filepath>.

In success, it returns true. In failure, it returns false and the error will be logged.


=head2 $is_success = $storage->load($filepath)

Loads statuses from the file named C<$filepath>.

In success, it returns true. In failure, it returns false and the error will be logged.


=head1 AUTHOR

Toshio Ito C<< toshioito [at] cpan.org >>

=cut
