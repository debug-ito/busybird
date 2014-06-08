package BusyBird::StatusStorage::Common;
use strict;
use warnings;
use Carp;
use CPS qw(kforeach);
use Exporter qw(import);

our @EXPORT_OK = qw(contains);

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
