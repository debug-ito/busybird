package BusyBird::Util;
use strict;
use warnings;
use Scalar::Util ('blessed');
use Carp;
use Exporter qw(import);
use BusyBird::DateTime::Format;
use DateTime;
use 5.10.0;
use BusyBird::Version;
our $VERSION = $BusyBird::Version::VERSION;


our @EXPORT_OK = (qw(set_param expand_param sort_statuses split_with_entities));

sub set_param {
    my ($hashref, $params_ref, $key, $default, $is_mandatory) = @_;
    if($is_mandatory && !defined($params_ref->{$key})) {
        my $classname = blessed $hashref;
        croak "ERROR: set_param in $classname: Parameter for '$key' is mandatory, but not supplied.";
    }
    $hashref->{$key} = (defined($params_ref->{$key}) ? $params_ref->{$key} : $default);
}

sub expand_param {
    my ($param, @names) = @_;
    my $refparam = ref($param);
    my @result = ();
    if($refparam eq 'ARRAY') {
        @result = @$param;
    }elsif($refparam eq 'HASH') {
        @result = @{$param}{@names};
    }else {
        $result[0] = $param;
    }
    return wantarray ? @result : $result[0];
}

sub _epoch_undef {
    my ($datetime_str) = @_;
    my $dt = BusyBird::DateTime::Format->parse_datetime($datetime_str);
    return defined($dt) ? $dt->epoch : undef;
}

sub _sort_compare {
    my ($a, $b) = @_;
    if(defined($a) && defined($b)) {
        return $b <=> $a;
    }elsif(!defined($a) && defined($b)) {
        return -1;
    }elsif(defined($a) && !defined($b)) {
        return 1;
    }else {
        return 0;
    }
}

sub sort_statuses {
    my ($statuses) = @_;
    use sort 'stable';
    
    my @dt_statuses = do {
        no autovivification;
        map {
            my $acked_at = $_->{busybird}{acked_at}; ## avoid autovivification
            [
                $_,
                _epoch_undef($acked_at),
                _epoch_undef($_->{created_at}),
            ];
        } @$statuses;
    };
    return [ map { $_->[0] } sort {
        foreach my $sort_key (1, 2) {
            my $ret = _sort_compare($a->[$sort_key], $b->[$sort_key]);
            return $ret if $ret != 0;
        }
        return 0;
    } @dt_statuses];
}

sub _create_text_segment {
    return {
        text => substr($_[0], $_[1], $_[2] - $_[1]),
        start => $_[1],
        end => $_[2],
        type => $_[3],
        entity => $_[4],
    };
}

sub split_with_entities {
    my ($text, $entities_hashref) = @_;
    use sort 'stable';
    if(!defined($text)) {
        croak "text must not be undef";
    }
    $entities_hashref = {} if not defined $entities_hashref;

    ## create entity segments
    my @entity_segments = ();
    foreach my $entity_type (keys %$entities_hashref) {
        foreach my $entity (@{$entities_hashref->{$entity_type}}) {
            push(@entity_segments, _create_text_segment(
                $text, $entity->{indices}[0], $entity->{indices}[1], $entity_type, $entity
            ));
        }
    }
    @entity_segments = sort { $a->{start} <=> $b->{start} } @entity_segments;

    ## combine entity_segments with non-entity segments
    my $pos = 0;
    my @final_segments = ();
    foreach my $entity_segment (@entity_segments) {
        if($pos < $entity_segment->{start}) {
            push(@final_segments, _create_text_segment(
                $text, $pos, $entity_segment->{start}
            ));
        }
        push(@final_segments, $entity_segment);
        $pos = $entity_segment->{end};
    }
    if($pos < length($text)) {
        push(@final_segments, _create_text_segment(
            $text, $pos, length($text)
        ));
    }
    return \@final_segments;
}


1;

__END__

=pod

=head1 NAME

BusyBird::Util - utility functions for BusyBird


=for test_synopsis
my $timeline;

=head1 SYNOPSIS

    use BusyBird::Util qw(sort_statuses split_with_entities future_of);
    
    my @statuses;
    future_of($timeline, "get_statuses", count => 100)->then(sub {
        my ($statuses) = @_;
        @statuses = @$statuses;
    })->catch(sub {
        my ($error, $is_normal_error) = @_;
        warn $error;
    });
    
    my @sorted_statuses = sort_statuses(@statuses);
    
    my $status = $sorted_statuses[0];
    my $segments_arrayref = split_with_entities($status->{text}, $status->{entities});


=head1 DESCRIPTION

This module provides some utility functions useful in L<BusyBird>.

By default, this module exports nothing.

=head1 EXPORTABLE FUNCTIONS

=head2 @sorted = sort_statuses(@statuses)

Sorts an array of status object appropriately.

The sort refers to C<< $status->{created_at} >> and C<< $status->{busybird}{acked_at} >> fields.
See L<BusyBird::StatusStorage/Order_of_Statuses> section.

=head2 $segments_arrayref = split_with_entities($text, $entities_hashref)

Splits the given C<$text> with the "entities" and returns the split segments.

C<$text> is a string to be split. C<$entities_hashref> is a hash-ref which has the same stucture as
L<Twitter Entities|https://dev.twitter.com/docs/platform-objects/entities>.
Each entity object annotates a part of C<$text> with such information as linked URLs, mentioned users,
mentioned hashtags, etc.

The return value C<$segments_arrayref> is an array-ref of "segment" objects.
A "segment" is a hash-ref containing a part of C<$text> and the entity object (if any) attached to it.
Note that C<$segments_arrayref> has segments that no entity is attached to.
C<$segments_arrayref> is sorted, so you can assemble the complete C<$text> by concatenating all the segments.

Example:

    my $text = 'aaa --- bb ---- ccaa -- ccccc';
    my $entities = {
        a => [
            {indices => [0, 3],   url => 'http://hoge.com/a/1'},
            {indices => [18, 20], url => 'http://hoge.com/a/2'},
        ],
        b => [
            {indices => [8, 10], style => "bold"},
        ],
        c => [
            {indices => [16, 18], footnote => 'first c'},
            {indices => [24, 29], some => {complex => 'structure'}},
        ],
        d => []
    };
    my $segments = split_with_entities($text, $entities);
    
    ## $segments = [
    ##     { text => 'aaa', start => 0, end => 3, type => 'a',
    ##       entity => {indices => [0, 3], url => 'http://hoge.com/a/1'} },
    ##     { text => ' --- ', start => 3, end => 8, type => undef,
    ##       entity => undef},
    ##     { text => 'bb', start => 8, end => 10, type => 'b',
    ##       entity => {indices => [8, 10], style => "bold"} },
    ##     { text => ' ---- ', start => 10, end =>  16, type => undef,
    ##       entity => undef },
    ##     { text => 'cc', start => 16, end => 18, type => 'c',
    ##       entity => {indices => [16, 18], footnote => 'first c'} },
    ##     { text => 'aa', start => 18, end => 20, type => 'a',
    ##       entity => {indices => [18, 20], url => 'http://hoge.com/a/2'} },
    ##     { text => ' -- ', start => 20, end => 24, type => undef,
    ##       entity => undef },
    ##     { text => 'ccccc', start => 24, end => 29, type => 'c',
    ##       entity => {indices => [24, 29], some => {complex => 'structure'}} }
    ## ];

Any entity object is required to have C<indices> field, which is an array-ref
of starting and ending indices of the text part.
The ending index must be greater than or equal to the starting index.
Other fields in entity objects are optional.

Entity objects must not overlap. In that case, the result is undefined.

A segment hash-ref has the following fields.

=over

=item C<text>

Substring of the C<$text>.

=item C<start>

Starting index of the segment in C<$text>.

=item C<end>

Ending index of the segment in C<$text>.

=item C<type>

Type of the entity. If the segment has no entity attached, it is C<undef>.

=item C<entity>

Attached entity object. If the segment has no entity attached, it is C<undef>.

=back

It croaks if C<$text> is C<undef>.


=head2 $future = future_of($invocant, $method, %args)

Wraps a callback-style method call with a L<Future::Q> object.

This function executes C<< $invocant->$method(%args) >>, which is supposed to be a callback-style method.
Before the execution, C<callback> field in C<%args> is overwritten, so that the result of the callback can be
obtained from C<$future>.

To use C<future_of()>, the C<$method> must conform to the following specification.
(Most of L<BusyBird::Timeline>'s callback-style methods follow this specification)

=over

=item *

The C<$method> takes named arguments as in C<< $invocant->$method(key1 => value1, key2 => value2 ... ) >>.

=item *

When the C<$method>'s operation is done, the subroutine reference stored in C<$args{callback}> must be called exactly once.

=item *

C<$args{callback}> must be called as in

    $args{callback}->($error, @results)

=item *

In success, the C<$error> must be a falsy scalar and the rest of the arguments is the result of the operation.
The arguments other than C<$error> are used to fulfill the C<$future>.

=item *

In failure, the C<$error> must be a truthy scalar that describes the error.
The C<$error> is used to reject the C<$future>.

=back

The return value (C<$future>) is a L<Future::Q> object, which represents the result of the C<$method> call.
If C<$method> throws an exception, it is caught by C<future_of()> and C<$future> becomes rejected.

In success, C<$future> is fulfilled with the results the C<$method> returns.

    $future->then(sub {
        my @results = @_;
        ...
    });

In failure, C<$future> is rejected with the error and a flag.

    $future->catch(sub {
        my ($error, $is_normal_error) = @_;
        ...
    });

If C<$error> is the error passed to the callback, C<$is_normal_error> is true.
If C<$error> is the exception the method throws, C<$is_normal_error> does not even exist.


=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut
