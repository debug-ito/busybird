package BusyBird::Status;
use strict;
use warnings;
use JSON;
use DateTime;


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
        datetime => $self->getDateTime->strftime('%Y/%m/%dT%H:%M:%S%z'),
    };
    return encode_json($obj);
}

1;


