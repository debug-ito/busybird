package BusyBird::Object;

sub _setParam {
    my ($self, $params_ref, $key, $default, $is_mandatory) = @_;
    if($is_mandatory && !defined($params_ref->{$key})) {
        my $classname = blessed $self;
        die "ERROR: _setParam in $classname: Parameter for '$key' is mandatory, but not supplied.";
    }
    $self->{$key} = (defined($params_ref->{$key}) ? $params_ref->{$key} : $default);
}

sub objectStates {
    my ($class, @event_names) = @_;
    my %object_state = ();
    foreach my $event (@event_names) {
        my $method_name = $event;
        $method_name =~ s/^(.)/uc($1)/e;
        $method_name =~ s/_(.)/uc($1)/eg;
        $method_name = '_session' . $method_name;
        $object_state{$event} = $method_name;
    }
    return \%object_state;
}


1;



