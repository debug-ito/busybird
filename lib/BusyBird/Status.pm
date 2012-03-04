package BusyBird::Status;
use strict;
use warnings;
use JSON;
use DateTime;

my @MONTH = (undef, qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec));
my @DAY_OF_WEEK = (undef, qw(Mon Tue Wed Thu Fri Sat Sun));

sub getJSON {
    my ($self) = @_;
    my $obj = {
        bb_input_name => $self->getInputName,
        bb_datetime => $self->getDateTime->strftime('%Y/%m/%dT%H:%M:%S%z'),
        id => $self->getID,
        created_at => sprintf("%s %s %s",
                              $DAY_OF_WEEK[$self->getDateTime->day_of_week],
                              $MONTH[$self->getDateTime->month],
                              $self->getDateTime->strftime('%e %H:%M:%S %z %Y')),
        text => $self->getText,
        user => {
            screen_name => $self->getSourceName,
            name => $self->getSourceNameAlt,
            profile_image_url => $self->getIconURL,
        },
        in_reply_to_screen_name => $self->getReplyToName,
    };
    return encode_json($obj);
}

1;


