package BusyBird;
use strict;
use warnings;
use File::ShareDir qw(dist_dir);


sub sharedir {
    return dist_dir(__PACKAGE__);
}

our $VERSION = '0.01';

1;
