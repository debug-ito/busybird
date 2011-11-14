package BusyBird::Judge;
use strict;
use warnings;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub addScore {
    my ($self, $statuses) = @_;
    ## ** $statuses is a referece to an array of BusyBird statuses.
    
    ## ** STUB
    foreach my $status (@$statuses) {
        $status->setScore(1.0);
    }
}

1;
