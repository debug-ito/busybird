#!/usr/bin/env perl
use strict;
use warnings;
use Daiku;
use FindBin;
use autodie ":all";

my @icon_bases = qw(favicon_alert favicon_normal);
my $here = $FindBin::RealBin;

sub get_icon_dest { "$here/../share/www/static/$_[0].ico" }

task 'all' => [map { get_icon_dest($_) } @icon_bases];

foreach my $icon_base (@icon_bases) {
    my $source = "$here/$icon_base.svg";
    my $middle = "$here/$icon_base.png";
    my $dest = get_icon_dest($icon_base);
    file $dest, $source, sub {
        system("inkscape -e $middle $source");
        system("convert $middle $dest");
        unlink $middle;
    };
}

build shift @ARGV || 'all';

