package BusyBird::DateTime::Format;
use strict;
use warnings;
use DateTime::Format::Strptime;
use Try::Tiny;

our $preferred = 0;

my %OPT_DEFAULT = (
    locale => 'en_US',
    on_error => 'undef',
);

my @FORMATS = (
    DateTime::Format::Strptime->new(
        %OPT_DEFAULT,
        pattern => '%a %b %d %T %z %Y',
    ),
    DateTime::Format::Strptime->new(
        %OPT_DEFAULT,
        pattern => '%a, %d %b %Y %T %z',
    ),
);

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub parse_datetime {
    my ($class_self, $string) = @_;
    my $parsed;
    return undef if not defined $string;
    foreach my $f (@FORMATS) {
        $parsed = try {
            $f->parse_datetime($string);
        }catch {
            undef;
        };
        last if defined($parsed);
    }
    return $parsed;
}

sub format_datetime {
    my ($class_self, $datetime) = @_;
    return $FORMATS[$preferred]->format_datetime($datetime);
}

1;

=pod

=head1 NAME

BusyBird::DateTime::Format - DateTime::Format for BusyBird

=head1 SYNOPSIS

    use BusyBird::DateTime::Format;
    my $f = 'BusyBird::DateTime::Format';

    ## Twitter API format
    my $dt1 = $f->parse_datetime('Fri Feb 08 11:02:15 +0900 2013');

    ## Twitter Search API format
    my $dt2 = $f->parse_datetime('Sat, 16 Feb 2013 23:02:54 +0000');

    my $str = $f->format_datetime($dt2);
    ## $str: 'Sat Feb 16 23:02:54 +0000 2013'


=head1 DESCRIPTION

This class is the standard DateTime::Format in L<BusyBird>.

It can parse the following format.

=over

=item *

'created_at' format of Twitter API.

=item *

'created_at' format of Twitter Search API v1.0.

=back

It formats L<DateTime> object in 'created_at' format of Twitter API.


=head1 CLASS METHODS

=head2 $f = BusyBird::DateTime::Format->new()

Creates a formatter.

=head1 CLASS AND OBJECT METHODS

The following methods can apply both to class and to an object.

=head2 $datetime = $f->parse_datetime($string)

Parse C<$string> to get L<DateTime> object.

If given an improperly formatted string, this method returns C<undef>. It NEVER croaks.

=head2 $string = $f->format_datetime($datetime)

Format L<DateTime> object to a string.


=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>


=cut

