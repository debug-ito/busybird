package BusyBird::Worker::Twitter;
use base ('BusyBird::Worker::Object');

use strict;
use warnings;
use Net::Twitter;

sub new {
    my ($class, %net_twitter_params) = @_;
    $net_twitter_params{traits} ||= [qw(API::REST API::Lists)];
    $net_twitter_params{ssl}    = 1 if !defined($net_twitter_params{ssl});
    my $nt = Net::Twitter->new(%net_twitter_params);
    my $self = $class->SUPER::new($nt);
    ## $self->{apiurl} = ($net_twitter_params{apiurl} or '_DEFAULT_');
    return $self;
}

sub getAPIURL {
    my $self = shift;
    return $self->getTargetObject->apiurl;
    ## return $self->{apiurl};
}

1;

