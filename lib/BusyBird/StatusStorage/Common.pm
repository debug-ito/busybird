package BusyBird::StatusStorage::Common;
use strict;
use warnings;
use Carp;
use CPS qw(kforeach kpar);
use CPS::Functional qw(kmap);
use Exporter qw(import);
use BusyBird::DateTime::Format;
use DateTime;
use Try::Tiny;

our @EXPORT_OK = qw(contains ack_statuses get_unacked_counts);

sub ack_statuses {
    my ($self, %args) = @_;
    croak 'timeline arg is mandatory' if not defined $args{timeline};
    my $ids;
    if(defined($args{ids})) {
        if(!ref($args{ids})) {
            $ids = [$args{ids}];
        }elsif(ref($args{ids}) eq 'ARRAY') {
            $ids = $args{ids};
            croak "ids arg array must not contain undef" if grep { !defined($_) } @$ids;
        }else {
            croak "ids arg must be either undef, status ID or array-ref of IDs";
        }
    }
    my $max_id = $args{max_id};
    my $timeline = $args{timeline};
    my $callback = $args{callback} || sub {};
    my $ack_str = BusyBird::DateTime::Format->format_datetime(
        DateTime->now(time_zone => 'UTC')
    );
    my @target_statuses = ();
    my $method_error;
    kpar sub {
        my $done = shift;
        _get_unacked_statuses_by_ids($self, $timeline, $ids, sub {
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
        @target_statuses = _uniq_statuses(@target_statuses);
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

sub contains {
    my ($self, %args) = @_;
    my $timeline = $args{timeline};
    my $query = $args{query};
    my $callback = $args{callback};
    croak 'timeline argument is mandatory' if not defined($timeline);
    croak 'query argument is mandatory' if not defined($query);
    croak 'callback argument is mandatory' if not defined($callback);
    if(ref($query) eq 'ARRAY') {
        ;
    }elsif(ref($query) eq 'HASH' || !ref($query)) {
        $query = [$query];
    }else {
        croak 'query argument must be either STATUS, ID or ARRAYREF_OF_STATUSES_OR_IDS';
    }
    if(grep { !defined($_) || ( ref($_) eq "HASH" && !defined($_->{id}) ) } @$query) {
        croak 'query argument must specify ID';
    }
    my @contained = ();
    my @not_contained = ();
    my $error_occurred = 0;
    my $error;
    kforeach $query, sub {
        my ($query_elem, $knext, $klast) = @_;
        my $id = ref($query_elem) ? $query_elem->{id} : $query_elem;
        $self->get_statuses(timeline => $timeline, count => 1, max_id => $id, callback => sub {
            $error = shift;
            my $statuses = shift;
            if(defined($error)) {
                $error_occurred = 1;
                $klast->();
                return;
            }
            if(@$statuses) {
                push(@contained, $query_elem);
            }else {
                push(@not_contained, $query_elem);
            }
            $knext->();
        });
    }, sub {
        if($error_occurred) {
            $callback->("get_statuses error: $error");
            return;
        }
        $callback->(undef, \@contained, \@not_contained);
    };
}

sub get_unacked_counts {
    my ($self, %args) = @_;
    croak 'timeline arg is mandatory' if not defined $args{timeline};
    croak 'callback arg is mandatory' if not defined $args{callback};
    my $timeline = $args{timeline};
    my $callback = $args{callback};
    $self->get_statuses(
        timeline => $timeline, ack_state => "unacked", count => "all",
        callback => sub {
            my ($error, $statuses) = @_;
            if(defined($error)) {
                @_ = ("get error: $error");
                goto $callback;
            }
            my %count = (total => int(@$statuses));
            foreach my $status (@$statuses) {
                my $level = do {
                    no autovivification;
                    $status->{busybird}{level} || 0;
                };
                $count{$level}++;
            }
            @_ = (undef, \%count);
            goto $callback;
        }
    );
}


1;
__END__

=pod

=head1 NAME

BusyBird::StatusStorage::Common - common partial implementation of StatusStorage

=head1 SYNOPSIS

    package My::StatusStorage;
    use parent "BusyBird::StatusStorage";
    use BusyBird::StatusStorage::Common qw(ack_statuses get_unacked_counts contains);
    
    sub new { ... }
    sub get_statuses { ... }
    sub put_statuses { ... }
    sub delete_statuses { ... }
    
    1;

=head1 DESCRIPTION

This module implements and exports some methods required by L<BusyBird::StatusStorage> interface.

To import methods from L<BusyBird::StatusStorage::Common>, the importing class must implement C<get_statuses()> and C<put_statuses>.
This is because exported methods in L<BusyBird::StatusStorage::Common> use those methods.

=head1 EXPORTABLE FUNCTIONS

The following methods are exported only by request.

=head2 ack_statuses

=head2 get_unacked_counts

=head2 contains

See L<BusyBird::StatusStorage>.


=head1 AUTHOR

Toshio Ito C<< <toshioito@cpan [at] org> >>

=cut
