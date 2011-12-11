package BusyBird::Status;
use strict;
use warnings;
use JSON;


sub getJSON {
    my ($self) = @_;
    my $obj = {
        id => $self->getID,
        input_name => $self->getInputName,
        text => $self->getText,
        source_name => $self->getSourceName,
        source_name_alt => $self->getSourceNameAlt,
        icon_url => $self->getIconURL,
        reply_to => $self->getReplyToName,
    };
    return encode_json($obj);
}

1;


