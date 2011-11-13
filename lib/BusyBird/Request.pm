package BusyBird::Request;
use strict;
use warnings;

use POE::Wheel::ReadWrite;

sub new {
    my ($class, $point, $client, $detail) = @_;
    return bless {point => $point, client => $client, detail => $detail}, $class;
}

sub getPoint { my $self = shift; return $self->{point} }
sub getClient { my $self = shift; return $self->{client} }
sub getDetail { my $self = shift; return $self->{detail} }

sub getID {
    my $self = shift;
    return ($self->getClient->ID . "_" . $self->getPoint);
}

1;
