package BusyBird::Status::Buffer;

use strict;
use warnings;
use BusyBird::Status;
use BusyBird::Util qw(setParam :datetime);

sub new {
    my ($class, %params) = @_;
    my $self = bless {
        buffer => [],
        dict => {},
    }, $class;
    $self->setParam(\%params, 'max_size', 0);
    return $self;
}

sub get {
    my ($self, $start_index, $entry_num) = @_;
    my $statuses_num = $self->size;
    $start_index = 0 if !defined($start_index);
    if($start_index >= $statuses_num) {
        return [];
    }
    if($start_index < 0) {
        $start_index += $statuses_num;
        if($start_index < 0) {
            return [];
        }
    }
    $entry_num = $statuses_num - $start_index if !defined($entry_num);
    if($entry_num == 0) {
        return [];
    }
    my $end_inc_index;
    if($entry_num > 0) {
        $end_inc_index = $start_index + $entry_num - 1;
        $end_inc_index = $statuses_num - 1 if $end_inc_index >= $statuses_num;
    }else {
        $end_inc_index = $statuses_num - 1 + $entry_num;
    }
    return [ @{$self->{buffer}}[$start_index .. $end_inc_index] ];
}

sub unshift {
    my ($self, @statuses) = @_;
    @statuses = grep {!$self->contains($_)} @statuses;
    CORE::unshift(@{$self->{buffer}}, @statuses);
    @{$self->{dict}}{map {$_->{id}} @statuses} = @statuses;
    return $self;
}

sub size {
    my ($self) = @_;
    return int(@{$self->{buffer}});
}

sub truncate {
    my ($self) = @_;
    return if !defined($self->{max_size}) || $self->{max_size} <= 0;
    while(int(@{$self->{buffer}}) > $self->{max_size}) {
        my $discarded_status = pop(@{$self->{buffer}});
        delete $self->{dict}{$discarded_status->{id}};
    }
    return $self;
}

sub clear {
    my ($self) = @_;
    @{$self->{buffer}} = ();
    %{$self->{dict}} = ();
    return $self;
}

sub contains {
    my ($self, $id_or_status) = @_;
    my $id = ref($id_or_status) ? $id_or_status->{id} : $id_or_status;
    return defined($self->{dict}{$id});
}

sub sort {
    my ($self, $sorter) = @_;
    my @sorted_statuses;
    if(defined($sorter)) {
        @sorted_statuses = CORE::sort { $sorter->($a, $b) } @{$self->{buffer}};
    }else {
        @sorted_statuses = map { $_->[0] }
            CORE::sort { DateTime->compare($b->[1], $a->[1]) }
            map { [$_, datetimeParse($_->{created_at})] } @{$self->{buffer}};
    }
    $self->{buffer} = \@sorted_statuses;
    return $self;
}

sub TO_JSON {
    my ($self) = @_;
    ## return [ map {$_->convertForJSON} @{$self->{buffer}} ];
    return $self->{buffer};
}
    

1;
