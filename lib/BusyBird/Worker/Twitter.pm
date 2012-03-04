package BusyBird::Worker::Twitter;
use base ('BusyBird::Worker::Object');

use strict;
use warnings;
use Net::Twitter;

sub new {
    my ($class, %net_twitter_params) = @_;
    $net_twitter_params{traits} ||= [qw(OAuth API::REST API::Lists)];
    $net_twitter_params{ssl}    = 1 if !defined($net_twitter_params{ssl});
    my $nt = Net::Twitter->new(%net_twitter_params);
    return $class->SUPER::new($nt);
}

1;

