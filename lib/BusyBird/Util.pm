package BusyBird::Util;
use strict;
use warnings;
use Scalar::Util ('blessed');
use Carp;
use Exporter qw(import);
use BusyBird::DateTime::Format;
use DateTime;

our @EXPORT_OK = (qw(set_param expand_param sort_statuses));

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

1;

__END__

=pod

=head1 NAME

BusyBird::Util - utility functions for BusyBird

=head1 SYNOPSIS

    use BusyBird::Util qw(sort_statuses);
    
    my @sorted_statuses = sort_statuses(@statuses);

=head1 DESCRIPTION

This module provides some utility functions useful in L<BusyBird>.

By default, this module exports nothing.

=head1 EXPORTABLE FUNCTIONS

=head2 @sorted = sort_statuses(@statuses)

Sorts an array of status object appropriately.

The sort refers to C<< $status->{created_at} >> and C<< $status->{busybird}{acked_at} >> fields.
See L<BusyBird::StatusStorage/Order_of_Statuses> section.

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut
