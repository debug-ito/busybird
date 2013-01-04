package App::BusyBird::DateTime::Format;
use strict;
use warnings;
use DateTime::Format::Strptime;
use DateTime::Format::RFC3339;
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
    DateTime::Format::RFC3339->new(),
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

App::BusyBird::DateTime::Format - DateTime::Format for App::BusyBird

=head1 DESCRIPTION

This class is the standard DateTime::Format in App::BusyBird.

It can parse the following format.

=over

=item *

'created_at' format of Twitter API.

=item *

'created_at' format of Twitter Search API v1.0.

=item *

RFC3339 format. See L<DateTime::Format::RFC3339>.

=back

It formats L<DateTime> object in 'created_at' format of Twitter API.


=head1 CLASS METHODS

=head2 $f = App::BusyBird::DateTime::Format->new()

Creates a formatter.

=head1 CLASS AND OBJECT METHODS

The following methods can apply both to class and to an object.

=head2 $datetime = $f->parse_datetime($string)

Parse C<$string> to get L<DateTime> object.

If given an improperly formatted string, this method returns C<undef>. It NEVER croaks.

=head2 $string = $f->format_datetime($datetime)

Format L<DateTime> object to a string.


=head1 AUTHOR

Toshio Ito 


=cut

