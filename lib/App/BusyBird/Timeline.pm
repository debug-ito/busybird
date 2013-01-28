package App::BusyBird::Timeline;
use strict;
use warnings;
use App::BusyBird::Util qw(set_param);
use App::BusyBird::Log;
use Carp;
use CPS qw(kforeach);

our @CARP_NOT = ();

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    $self->set_param(\%args, 'name', undef, 1);
    $self->set_param(\%args, 'storage', undef, 1);
    $self->set_param(\%args, 'logger', App::BusyBird::Log->logger);
    croak 'name must not be empty' if $self->{name} eq '';
    croak 'name must consist only of [a-zA-Z0-9_-]' if $self->{name} !~ /^[a-zA-Z0-9_-]+$/;
    return $self;
}

sub name {
    return shift->{name};
}

sub get_statuses {
    my ($self, %args) = @_;
    $args{timeline} = $self->name;
    local @CARP_NOT = (ref($self->{storage}));
    $self->{storage}->get_statuses(%args);
}

sub get_unacked_counts {
    my ($self, %args) = @_;
    $args{timeline} = $self->name;
    local @CARP_NOT = (ref($self->{storage}));
    $self->{storage}->get_unacked_counts(%args);
}

sub _write_statuses {
    my ($self, $method, $args_ref) = @_;
    $args_ref->{timeline} = $self->name;
    local @CARP_NOT = (ref($self->{storage}));
    $self->{storage}->$method(%$args_ref);
}

sub put_statuses {
    my ($self, %args) = @_;
    $self->_write_statuses('put_statuses', \%args);
}

sub delete_statuses {
    my ($self, %args) = @_;
    $self->_write_statuses('delete_statuses', \%args);
}

sub ack_statuses {
    my ($self, %args) = @_;
    $self->_write_statuses('ack_statuses', \%args);
}

sub add_statuses {
    my ($self, %args) = @_;
    $args{mode} = 'insert';
    $self->_write_statuses('put_statuses', \%args);
}

sub add {
    my ($self, $statuses, $callback) = @_;
    $self->add_statuses(statuses => $statuses, callback => $callback);
}

sub contains {
    my ($self, %args) = @_;
    my $query = $args{query};
    my $callback = $args{callback};
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
        $self->get_statuses(count => 1, max_id => $id, callback => sub {
            if(@_ >= 2) {
                $error_occurred = 1;
                $error = $_[1];
                $klast->();
                return;
            }
            my $statuses = shift;
            if(@$statuses) {
                push(@contained, $query_elem);
            }else {
                push(@not_contained, $query_elem);
            }
            $knext->();
        });
    }, sub {
        if($error_occurred) {
            $callback->(undef, undef, "get_statuses error: $error");
            return;
        }
        $callback->(\@contained, \@not_contained);
    };
}


our $VERSION = '0.01';

1;

=pod

=head1 NAME

App::BusyBird::Timeline - a timeline object in BusyBird

=head1 VERSION

0.01

=head1 SYNOPSIS

=head1 DESCRIPTION

L<App::BusyBird::Timeline> stores and manages a timeline, which is an ordered sequence of statuses.
You can add statuses to a timeline, and get statuses from the timeline.

You can set status filters to a timeline.
A status filter is a subroutine that is called when new statuses are added to the timeline
via C<add_statuses()> method.
Using status filters, you can modify or even drop the added statuses before they are
actually inserted to the timeline.
Statuse filters are executed in the same order as they are added.


=head1 CLASS METHODS

=head2 $timeline = App::BusyBird::Timeline->new(%args)

Creates a new timeline.

You can create a timeline via L<App::BusyBird::Main>'s C<timeline()> method,
but C<new()> method allows for more detailed customization.

Fields in C<%args> are as follows.

=over

=item C<name> => STRING (mandatory)

Specifies the name of the timeline.
It must be a string consisting only of C<[a-zA-Z0-9_-]>.

=item C<storage> => STATUS_STORAGE (mandatory)

Specifies the status storage object that implements the interface documented in L<App::BusyBird::StatusStorage>.
Statuses in C<$timeline> is saved to the C<storage>.

=item C<logger> => CODEREF($level, $msg) (optional, default: C<< App::BusyBird::Log->logger >>)

Specifies the logger subroutine reference.
See L<App::BusyBird::Log> for the spec of the logger.

=back


=head1 OBJECT METHODS

=head2 $name = $timeline->name()

Returns the C<$timeline>'s name.

=head2 $timeline->add($statuses, [$callback])

=head2 $timeline->add_statuses(%args)

Adds new statuses to the C<$timeline>.

Note that statuses added by C<add_statuses()> method go through the C<$timeline>'s filters.
It is the filtered statuses that are actually inserted to the storage.

C<add()> method is a short-hand of C<< add_statuses(statuses => $statuses, callback => $callback) >>.

Fields in C<%args> are as follows.

=over

=item C<statuses> => ARRAYREF_OF_STATUSES (mandatory)

Specifies an array-ref of status objects to be added.
See L<App::BusyBird::Status> about what status objects look like.

=item C<callback> => CODEREF($added_num, $error) (optional, default: C<undef>)

Specifies a subroutine reference that is called when the operation has completed.
In success, C<callback> is called with one argument (C<$added_num>),
which is the number of statuses actually added to the C<$timeline>.
In failure, C<callback> is called with two arguments,
and the second argument (C<$error>) describes the error.

=back



=head2 $timeline->ack_statuses(%args)

Acknowledges statuses in the C<$timeline>, that is, changing 'unacked' statuses into 'acked'.

Acked status is a status whose C<< $status->{busybird}{acked_at} >> field evaluates to true.
Otherwise, the status is unacked.

Fields in C<%args> are as follows.

=over

=item C<max_id> => ID (optional, default: C<undef>)

Specifies the latest ID of the statuses to be acked.

If specified, unacked statuses with IDs older than or equal to the specified C<max_id> are acked.
If there is no unacked status with ID C<max_id>, no status is acked.

If this option is omitted or set to C<undef>, all unacked statuses are acked.


=item C<callback> => CODEREF($acked_num, $error) (optional, default: C<undef>)

Specifies a subroutine reference that is called when the operation completes.

In success, the C<callback> is called with one argument
(C<$acked_num>), which is the number of acked statuses.

In failure, the C<callback> is called with two arguments,
and the second one (C<$error>) describes the error.

=back



=head2 $timeline->get_statuses(%args)

Fetches statuses from the C<$timeline>.
The fetched statuses are given to the C<callback> function.

Fields in C<%args> are as follows.

=over

=item C<callback> => CODEREF($arrayref_of_statuses, $error) (mandatory)

Specifies a subroutine reference that is called upon completion of
fetching statuses.

In success, C<callback> is called with one argument
(C<$arrayref_of_statuses>), which is an array-ref of fetched status
objects.  The array-ref can be empty.

In failure, C<callback> is called with two arguments,
and the second argument (C<$error>) describes the error.


=item C<ack_state> => {'any', 'unacked', 'acked'} (optional, default: 'any')

Specifies the acked/unacked state of the statuses to be fetched.

By setting it to C<'unacked'>, this method returns only
unacked statuses from the storage. By setting it to
C<'acked'>, it returns only acked statuses.  By setting it to
C<'any'>, it returns both acked and unacked statuses.


=item C<max_id> => STATUS_ID (optional, default: C<undef>)

Specifies the latest ID of the statuses to be fetched.  It fetches
statuses with IDs older than or equal to the specified C<max_id>.

If there is no such status that has the ID equal to C<max_id> in
specified C<ack_state>, the result is an empty array-ref.

If this option is omitted or set to C<undef>, statuses starting from
the latest status are fetched.

=item C<count> => {'all', NUMBER} (optional)

Specifies the maximum number of statuses to be fetched.

If C<'all'> is specified, all statuses starting from C<max_id> in
specified C<ack_state> are fetched.

The default value of this option is up to implementation of the status storage
the C<$timeline> uses.

=back



=head2 $timeline->put_statuses(%args)

Inserts statuses to the C<$timeline> or updates statuses in the C<$timeline>.
This method is a super-set of C<add_statuses()> method.

Usually you should use C<add_statuses()> method to add new statuses to the C<$timeline>,
because statuses inserted by C<put_statuses()> bypasses the C<$timeline>'s filters.

Fields in C<%args> are as follows.

=over

=item C<mode> => {'insert', 'update', 'upsert'} (mandatory)

Specifies the mode of operation.

If C<mode> is C<"insert">, the statuses are inserted (added) to the
C<$timeline>.  If C<mode> is C<"update">, the statuses in the
C<$timeline> are updated to the given statuses.  If C<mode> is
C<"upsert">, statuses already in the C<$timeline> are updated while
statuses not in the C<$timeline> are inserted.

The statuses are identified by C<< $status->{id} >> field.  The
C<< $status->{id} >> field must be unique in the C<$timeline>.
So if C<mode> is C<"insert">, statuses whose ID is already in the C<$timeline>
are ignored and not inserted.


=item C<statuses> => {STATUS, ARRAYREF_OF_STATUSES} (mandatory)

The statuses to be saved in the C<$timeline>.  It is either a status object
or an array-ref of status objects.

See L<App::BusyBird::Status> for specification of status objects.


=item C<callback> => CODEREF($put_num, $error) (optional, default: C<undef>)

Specifies a subroutine reference that is called when the operation completes.

In success, C<callback> is called with one argument (C<$put_num>),
which is the number of statuses inserted or updated.

In failure, C<callback> is called with two arguments,
and the second argument (C<$error>) describes the error.


=back


=head2 $timeline->delete_statuses(%args)

Deletes statuses from the C<$timeline>.

Fields in C<%args> are as follows.

=over

=item C<ids> => {C<undef>, ID, ARRAYREF_OF_IDS} (mandatory)

Specifies the IDs (value of C<< $status->{id} >> field) of the
statuses to be deleted.

If it is a defined scalar, the status with the specified ID is
deleted.  If it is an array-ref of IDs, the statuses with those IDs
are deleted.  If it is C<undef>, all statuses in the C<$timeline> are deleted.


=item C<callback> => CODEREF($deleted_num, $error) (optional, default: C<undef>)

Specifies a subroutine reference that is called when the operation completes.

In success, the C<callback> is called with one argument (C<$deleted_num>),
which is the number of deleted statuses.

In failure, the C<callback> is called with two arguments,
and the second argument (C<$error>) describes the error.


=back


=head2 $timeline->get_unacked_counts(%args)

Fetches numbers of unacked statuses in the C<$timeline>.

Fields in C<%args> are as follows.

=over

=item C<callback> => CODEREF($unacked_counts, $error) (mandatory)

Specifies a subroutine reference that is called when the operation completes.

In success, the C<callback> is called with one argument (C<$unacked_counts>),
which is a hash-ref describing numbers of unacked statuses in each level.

In failure, the C<callback> is called with two arguments,
and the second argument (C<$error>) describes the error.

=back

Fields in C<%$unacked_counts> are as follows.

=over

=item LEVEL => COUNT_OF_UNACKED_STATUSES_IN_THE_LEVEL

Integer keys represent levels. The values is the number of
unacked statuses in the level.

A status's level is the C<< $status->{busybird}{level} >> field.
See L<App::BusyBird::Status> for detail.


=item C<total> => COUNT_OF_ALL_UNACKED_STATUSES

The key C<"total"> represents the total number of unacked statuses
in the timeline.

=back


=head2 $timeline->contains(%args)

Checks whether the given statuses (or IDs) are contained in the C<$timeline>.

Fields in C<%args> are as follows.

=over

=item C<query> => {STATUS, ID, ARRAYREF_OF_STATUSES_OR_IDS} (mandatory)

Specifies the statuses or IDs to be checked.

If it is a scalar, that value is treated as a status ID.
If it is a hash-ref, that object is treated as a status object.
If it is an array-ref,
elements in the array-ref are treated as status objects or IDs.
Status objects and IDs can be mixed in a single array-ref.

=item C<callback> => CODEREF($contained, $not_contained, $error) (mandatory)

Specifies a subroutine reference that is called when the check has completed.

In success, C<callback> is called with two arguments (C<$contained>, C<$not_contained>).
C<$contained> is an array-ref of given statuses or IDs that are contained in the C<$timeline>.
C<$not_contained> is an array-ref of given statuses or IDs that are NOT contained in the C<$timeline>.

In failure, C<$callback> is called with three arguments, and the third argument (C<$error>) describes the error.

=back


=head2 $timeline->add_filter($filter->($arrayref_of_statuses))

Add a status filter to the C<$timeline>.

C<$filter> is a subroutine reference that takes one argument (C<$arrayref_of_statuses>).

C<$arrayref_of_statuses> is an array-ref of statuses that is injected to the filter.
C<$filter> can use and modify the C<$arrayref_of_statuses>.

C<$filter> must return an array-ref of statuses, which is going to be passed to the next filter
(or the status storage if there is no next filter).
The return value of C<$filter> may be either C<$arrayref_of_statuses> or a new array-ref.

If C<$filter> returns anything other than an array-ref,
a warning is logged and C<$arrayref_of_statuses> is passed to the next.


=head2 $timeline->add_filter_async($filter->($arrayref_of_statuses, $done))

Add an asynchronous status filter to the C<$timeline>.

C<$filter> is a subroutine reference that takes two arguments (C<$arrayref_of_statuses>, C<$done>).
C<$arrayref_of_statuses> is an array-ref of statuses that is injected to the filter.
C<$done> is a subroutine reference.

Instead of returning the result, C<$filter> must call C<< $done->($result) >> when it completes the filtering task.
The argument to the C<$done> callback (C<$result>) is an array-ref, which is the result of the filter.


=head2 $watcher = $timeline->watch_updates(%watch_spec, $callback->($w, %updates))

TBW...

Where should I write the specification of updates?
Maybe Web API documetion is the right place.



=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut
