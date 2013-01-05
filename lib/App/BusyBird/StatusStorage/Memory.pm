package App::BusyBird::StatusStorage::Memory;
use strict;
use warnings;
use App::BusyBird::Util qw(set_param sort_statuses);
use App::BusyBird::DateTime::Format;
use DateTime;
use Carp;
use List::Util qw(min);

sub new {
    my ($class, %options) = @_;
    my $self = bless {
        timelines => {}, ## timelines should be always sorted.
    }, $class;
    $self->set_param(\%options, 'filepath', undef);
    return $self;
}

## sub _exists {
##     my ($self, $timeline, $id) = @_;
##     return exists($self->{indices}{$timeline}{$id});
## }

sub _index {
    my ($self, $timeline, $id) = @_;
    return -1 if not defined($self->{timelines}{$timeline});
    my $tl = $self->{timelines}{$timeline};
    my @ret = grep { $tl->[$_]{id} eq $id } 0..$#$tl;
    confess "multiple IDs in timeline $timeline." if int(@ret) >= 2;
    return int(@ret) == 0 ? -1 : $ret[0];
}

sub _confirmed {
    my ($self, $status) = @_;
    no autovivification;
    return $status->{busybird}{confirmed_at};
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
    my $put_count = 0;
    foreach my $status_index (reverse 0 .. $#$statuses) {
        my $s = $statuses->[$status_index];
        croak "{id} field is mandatory in statuses" if not defined $s->{id};
        my $tl_index = $self->_index($timeline, $s->{id});
        my $existent = ($tl_index >= 0);
        last if ($mode eq 'insert' && $existent) || ($mode eq 'update' && !$existent);
        my $is_insert = ($mode eq 'insert');
        if($mode eq 'upsert') {
            $is_insert = (!$existent);
        }
        if($is_insert) {
            unshift(@{$self->{timelines}{$timeline}}, $s);
        }else {
            ## update
            $self->{timelines}{$timeline}[$tl_index] = $s;
        }
        $put_count++;
    }
    if($put_count > 0) {
        $self->{timelines}{$timeline} = sort_statuses($self->{timelines}{$timeline});
    }
    if($args{callback}) {
        @_ = ($put_count);
        goto $args{callback};
    }
}

sub delete_statuses {
    my ($self, %args) = @_;
    croak 'timeline arg is mandatory' if not defined $args{timeline};
    my $timeline = $args{timeline};
    if(!$self->{timelines}{$timeline}) {
        if($args{callback}) {
            @_ = (0);
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
            $self->{timelines}{$timeline} = [];
        }
    }
    if($args{callback}) {
        @_ = ($delete_num);
        goto $args{callback};
    }
}

sub get_statuses {
    my ($self, %args) = @_;
    croak 'timeline arg is mandatory' if not defined $args{timeline};
    croak 'callback arg is mandatory' if not defined $args{callback};
    my $timeline = $args{timeline};
    if(!$self->{timelines}{$timeline}) {
        @_ = ([]);
        goto $args{callback};
    }
    my $confirm_state = $args{confirm_state} || 'any';
    my $max_id = $args{max_id};
    my $count = defined($args{count}) ? $args{count} : 20;
    my $confirm_test = $confirm_state eq 'unconfirmed' ? sub {
        !$self->_confirmed(shift);
    } : $confirm_state eq 'confirmed' ? sub {
        $self->_confirmed(shift);
    } : sub { 1 };
    my $start_index;
    if(defined($max_id)) {
        my $tl_index = $self->_index($timeline, $max_id);
        if($tl_index < 0) {
            @_ = ([]);
            goto $args{callback};
        }
        my $s = $self->{timelines}{$timeline}[$tl_index];
        if(!$confirm_test->($s)) {
            @_ = ([]);
            goto $args{callback};
        }
        $start_index = $tl_index;
    }
    my @indice = grep {
        if(!$confirm_test->($self->{timelines}{$timeline}[$_])) {
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
        $self->{timelines}{$timeline}[$_]
    } @indice[0 .. ($count-1)] ];

    @_ = ($result_statuses);
    goto $args{callback};
}

sub confirm_statuses {
    my ($self, %args) = @_;
    croak 'timeline arg is mandatory' if not defined $args{timeline};
    my $timeline = $args{timeline};
    if(!$self->{timelines}{$timeline}) {
        if($args{callback}) {
            @_ = (0);
            goto $args{callback};
        }
        return;
    }
    my $ids = $args{ids};
    my @target_statuses = ();
    if(defined($ids)) {
        if(!ref($ids)) {
            $ids = [$ids];
        }elsif(ref($ids) eq 'ARRAY') {
            ;
        }else {
            croak "ids arg must be undef/ID/ARRAYREF_OF_IDS";
        }
        @target_statuses = map {
            my $tl_index = $self->_index($timeline, $_);
            $tl_index < 0 ? () : ($self->{timelines}{$timeline}[$tl_index]);
        } @$ids;
    }else {
        @target_statuses = grep {
            !$self->_confirmed($_)
        } @{$self->{timelines}{$timeline}};
    }
    my $confirm_str = App::BusyBird::DateTime::Format->format_datetime(
        DateTime->now(time_zone => 'UTC')
    );
    $_->{busybird}{confirmed_at} = $confirm_str foreach @target_statuses;
    if($args{callback}) {
        @_ = (int(@target_statuses));
        goto $args{callback};
    }
}

sub get_unconfirmed_counts {
    my ($self, %args) = @_;
    croak 'timeline arg is mandatory' if not defined $args{timeline};
    my $timeline = $args{timeline};
    if(!$self->{timelines}{$timeline}) {
        return ( total => 0 );
    }
    my @statuses = grep {
        !$self->_confirmed($_)
    } @{$self->{timelines}{$timeline}};
    my %count = (total => int(@statuses));
    foreach my $status (@statuses) {
        my $level = do {
            no autovivification;
            $status->{busybird}{level} || 0;
        };
        $count{$level}++;
    }
    return %count;
}


1;

=pod

=head1 NAME

App::BusyBird::StatusStorage::Memory - Simple status storage in the process memory

=head1 DESCRIPTION

This module is an implementation of L<App::BusyBird::StatusStorage>.

This storage stores all statuses in the process memory. The stored statuses are
saved to a file when the storage object is DESTROYed
(or C<save()> method is called manually).
It tries to load statuses from the file when initialized.

=head1 CAVEATS

=over

=item *

Because this storage stores statuses in the process memory,
forked servers cannot share the storage.

=item *

Because this storage saves statuses into a file on C<DESTROY>,
it's up to server implementation if statuses are saved properly
when the process is terminated by a signal.
(If a terminating signal is not caught, C<DESTROY> is never called)

=back

=head1 CLASS METHODS

=head2 $storage = App::BusyBird::StatusStorage::Memory->new(%options)

Creates the storage object.

=head1 OBJECTS METHODS

All methods described in L<App::BusyBird::StatusStorage> are supported.



=cut
