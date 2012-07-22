package BusyBird::Output;
use base ('BusyBird::Connector');
use Encode;
use strict;
use warnings;
use DateTime;
use IO::File;
use Carp;
use Async::Selector;

use BusyBird::Filter;
use BusyBird::Status;
use BusyBird::Status::Buffer;
use BusyBird::ComponentManager;
use BusyBird::Log qw(bblog);
use BusyBird::Util ('setParam');

sub new {
    my ($class, %params) = @_;
    push(local @BusyBird::Util::CARP_NOT, __PACKAGE__);
    $params{max_old_statuses} ||= 1024;
    $params{max_new_statuses} ||= 2048;
    my $self = bless {
        new_status_buffer => BusyBird::Status::Buffer->new(max_size => $params{max_new_statuses}),
        old_status_buffer => BusyBird::Status::Buffer->new(max_size => $params{max_old_statuses}),
        selector => Async::Selector->new(),
        filters => {
            map { $_ => BusyBird::Filter->new() } qw(parent_input input new_status)
        },
    }, $class;
    $self->setParam(\%params, 'name', undef, 1);
    $self->setParam(\%params, 'no_persistent', 0);
    $self->setParam(\%params, 'sync_with_input', 0);
    $self->setParam(\%params, 'auto_confirm', 0);
    $self->_initFilters();
    $self->_initSelector();
    BusyBird::ComponentManager->register('output', $self);
    return $self;
}

sub _initSelector {
    my ($self) = @_;
    $self->{selector}->register(
        new_statuses => sub {
            my $in = shift;
            $in = int($in);
            return $self->{new_status_buffer}->size > $in
                ? $self->{new_status_buffer}->get
                    : undef;
        }
    );
}

sub _getStatusesFilePath {
    my ($self) = @_;
    return "bboutput_" . $self->getName() . "_statuses.json";
}

sub saveStatuses {
    my ($self, $force) = @_;
    return if $self->{no_persistent} && !$force;
    my $serialized_statuses = BusyBird::Status->serialize(
        [@{$self->{new_status_buffer}->get}, @{$self->{old_status_buffer}->get}]
    );
    my $filepath = $self->_getStatusesFilePath();
    my $file = IO::File->new();
    if(!$file->open($filepath, "w")) {
        croak "Cannot open $filepath to write to.";
    }
    $file->print($serialized_statuses);
    $file->close();
    &bblog("Output " . $self->getName . ": Statuses are saved to $filepath.");
}

sub loadStatuses {
    my ($self, $force) = @_;
    return if $self->{no_persistent} && !$force;
    my $filepath = $self->_getStatusesFilePath();
    my $file = IO::File->new();
    if(!$file->open($filepath, "r")) {
        croak "Cannot open $filepath to read.";
    }
    my $data;
    {
        local $/ = undef;
        $data = $file->getline();
    }
    $file->close();
    my $deserialized = BusyBird::Status->deserialize($data);
    my @new_temp = ();
    my @old_temp = ();
    foreach my $des_status (@$deserialized) {
        my $is_new = $des_status->{busybird}{is_new};
        croak "Loaded status does not have busybird/is_new flag." if !defined($is_new);
        if($is_new) {
            push(@new_temp, $des_status);
        }else {
            push(@old_temp, $des_status);
        }
        ## my ($queue, $dict) = ($is_new)
        ##     ? ($self->{new_statuses}, $self->{new_ids})
        ##         : ($self->{old_statuses}, $self->{old_ids});
        ## push(@$queue, $des_status);
        ## $dict->{$des_status->{id}} = 1;
    }
    $self->{new_status_buffer}->clear->unshift(@new_temp);
    $self->{old_status_buffer}->clear->unshift(@old_temp);
    &bblog("Output " . $self->getName() . ": statuses are loaded from $filepath.");
    $self->{selector}->trigger('new_statuses');
}

sub _syncFilter {
    my ($self) = @_;
    return sub {
        my ($statuses, $cb) = @_;
        my %input_ids = map { $_->{id} => 1 } @$statuses;
        foreach my $buffer ($self->{new_status_buffer}, $self->{old_status_buffer}) {
            my @new_queue = ();
            foreach my $status (@{$buffer->get}) {
                if(defined($input_ids{$status->{id}})) {
                    push(@new_queue, $status);
                }
            }
            $buffer->clear->unshift(@new_queue);
        }
        $cb->($statuses);
    };
}

sub _initFilters {
    my ($self) = @_;
    $self->{filters}->{parent_input}->push(
        $self->{filters}->{input},
        $self->{sync_with_input} ? $self->_syncFilter : undef,
        sub {
            my ($statuses, $cb) = @_;
            $cb->($self->_uniqStatuses($statuses));
        },
        $self->{filters}->{new_status}
    );
}

sub getInputFilter {
    my $self = shift;
    return $self->{filters}->{input};
}

sub getNewStatusFilter {
    my $self = shift;
    return $self->{filters}->{new_status};
}

sub getName {
    my $self = shift;
    return $self->{name};
}

sub select {
    my ($self, $callback, %selections) = @_;
    $self->{selector}->select($callback, %selections);
}

sub _isUniqueID {
    my ($self, $id) = @_;
    return (!$self->{new_status_buffer}->contains($id) && !$self->{old_status_buffer}->contains($id));
    ## return (!defined($self->{old_ids}{$id})
    ##             && !defined($self->{new_ids}{$id}));
}

sub _uniqStatuses {
    my ($self, $statuses) = @_;
    my $uniq_statuses = [];
    foreach my $status (@$statuses) {
        if($self->_isUniqueID($status->{id})) {
            push(@$uniq_statuses, $status);
        }
    }
    return $uniq_statuses;
}

sub _sort {
    my ($self) = @_;
    $self->{new_status_buffer}->sort();
}

sub _getGlobalIndicesForStatuses {
    my ($self, $condition_func) = @_;
    my @indices = ();
    my $global_index = 0;
    foreach my $status (@{$self->{new_status_buffer}->get}, @{$self->{old_status_buffer}->get}) {
        local $_ = $status;
        push(@indices, $global_index) if &$condition_func();
        $global_index++;
    }
    return wantarray ? @indices : $indices[0];
}

sub _getStatuses {
    my ($self, $global_start_index, $entry_num) = @_;
    my $new_num = $self->{new_status_buffer}->size;
    my @entries = ();
    return \@entries if $entry_num <= 0;
    $global_start_index = 0 if $global_start_index < 0;
    my $old_entry_num = $entry_num;
    if($global_start_index < $new_num) {
        my $new_entries = $self->{new_status_buffer}->get($global_start_index, $entry_num);
        push(@entries, @$new_entries);
        $old_entry_num = $entry_num - int(@$new_entries);
    }
    if($old_entry_num > 0) {
        my $old_start_index = $global_start_index - $new_num;
        $old_start_index = 0 if $old_start_index < 0;
        my $old_entries = $self->{old_status_buffer}->get($old_start_index, $old_entry_num);
        push(@entries, @$old_entries);
    }
    return \@entries;
}

sub getNewStatuses {
    my ($self, $start_index, $entry_num) = @_;
    ## return $self->_getSingleStatuses($self->{new_statuses}, $start_index, $entry_num);
    return $self->{new_status_buffer}->get($start_index, $entry_num);
}

sub getOldStatuses {
    my ($self, $start_index, $entry_num) = @_;
    ## return $self->_getSingleStatuses($self->{old_statuses}, $start_index, $entry_num);
    return $self->{old_status_buffer}->get($start_index, $entry_num);
}

sub pushStatuses {
    my ($self, $statuses, $cb) = @_;
    $self->{filters}->{parent_input}->execute(
        $statuses, sub {
            my ($filtered_statuses) = @_;
            if(!@$filtered_statuses) {
                $cb->($filtered_statuses) if defined($cb);
                return;
            }
            ## unshift(@{$self->{new_statuses}}, @$filtered_statuses);
            foreach my $status (@$filtered_statuses) {
                ## $self->{new_ids}{$status->{id}} = 1;
                $status->{busybird}{is_new} = 1;
            }
            $self->{new_status_buffer}->unshift(@$filtered_statuses)->sort->truncate;
            
            ## $self->_sort();
            ## ## $self->_limitStatusQueueSize($self->{new_statuses}, $self->{max_new_statuses});
            ## $self->_limitStatusQueueSize('new');

            ## ** TODO: implement Nagle algorithm, i.e., delay the complete event a little to accept more statuses.
            $self->{selector}->trigger('new_statuses');
            &bblog(sprintf("Output %s: triggered. Now %d selections.", $self->getName, int($self->{selector}->selections)));
            $self->confirm if $self->{auto_confirm};
            $cb->($filtered_statuses) if defined($cb);
        }
    );
}

sub _getPointNameForCommand {
    my ($self, $com_name) = @_;
    return '/' . $self->getName() . '/' . $com_name;
}

sub confirm {
    my ($self) = @_;
    my $new_statuses = $self->{new_status_buffer}->get;
    $_->{busybird}{is_new} = 0 foreach @$new_statuses;
    $self->{old_status_buffer}->unshift(@$new_statuses)->truncate;
    $self->{new_status_buffer}->clear;
    $self->{selector}->trigger('new_statuses');
}

sub getPagedStatuses {
    my ($self, %params) = @_;
    my $DEFAULT_PER_PAGE = 20;
    ## my $new_num = int(@{$self->{new_statuses}});
    my $new_num = $self->{new_status_buffer}->size;
    my $page = $params{page};
    if($page && $page =~ /^[0-9]+$/) {
        $page = $page - 1;
    }else {
        $page = 0;
    }
    $page = 0 if $page < 0;
    
    my $per_page = $params{per_page};
    my $start_global_index = 0;
    my $end_global_index;

    if($params{max_id}) {
        $start_global_index = $self->_getGlobalIndicesForStatuses(sub { $_->{id} eq $params{max_id} });
        $start_global_index = 0 if !defined($start_global_index);
    }
    if($params{since_id}) {
        $end_global_index = $self->_getGlobalIndicesForStatuses(sub { $_->{id} eq $params{since_id} });
    }

    my ($get_start, $get_num);
    if($per_page && $per_page =~ /^[0-9]+$/) {
        ($get_start, $get_num) = ($start_global_index + $page * $per_page, $per_page);
    }else {
        $per_page = $DEFAULT_PER_PAGE;
        if($start_global_index < $new_num) {
            if($page == 0) {
                ($get_start, $get_num) = ($start_global_index, $per_page + $new_num - $start_global_index);
            }else {
                ($get_start, $get_num) = ($new_num + $page * $per_page, $per_page);
            }
        }else {
            ($get_start, $get_num) = ($start_global_index + $page * $per_page, $per_page);
        }
    }

    if(defined($end_global_index)) {
        my $num_to_end = $end_global_index - $get_start;
        $get_num = $num_to_end if $num_to_end < $get_num;
    }

    return $self->_getStatuses($get_start, $get_num);
}

sub c {
    my ($self, $to) = @_;
    return $self->SUPER::c(
        $to,
        'BusyBird::HTTPD' => sub {
            $to->addOutput($self);
        },
    );
}

1;
