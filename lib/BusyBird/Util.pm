package BusyBird::Util;
use strict;
use warnings;
use base ('Exporter');

our @EXPORT_OK = qw(setParam);

sub setParam {
    my ($hashref, $params_ref, $key, $default, $is_mandatory) = @_;
    if($is_mandatory && !defined($params_ref->{$key})) {
        my $classname = blessed $hashref;
        die "ERROR: _setParam in $classname: Parameter for '$key' is mandatory, but not supplied.";
    }
    $hashref->{$key} = (defined($params_ref->{$key}) ? $params_ref->{$key} : $default);
}



1;



