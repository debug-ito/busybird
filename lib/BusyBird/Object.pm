package BusyBird::Object;

sub _setParam {
    my ($self, $params_ref, $key, $default, $is_mandatory) = @_;
    if($is_mandatory && !defined($params_ref->{$key})) {
        my $classname = blessed $self;
        die "ERROR: _setParam in $classname: Parameter for '$key' is mandatory, but not supplied.";
    }
    $self->{$key} = (defined($params_ref->{$key}) ? $params_ref->{$key} : $default);
}


1;



