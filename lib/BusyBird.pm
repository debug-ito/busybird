package BusyBird;
use strict;
use warnings;
use File::ShareDir qw(dist_dir);

our $LOCAL_SHAREDIR = 0;

sub sharedir {
    return $LOCAL_SHAREDIR ? './share' : dist_dir(__PACKAGE__);
}

our $VERSION = '0.01';

1;
