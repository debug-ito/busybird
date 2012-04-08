package BusyBird::Status;
use strict;
use warnings;
use JSON;
use DateTime;

my @MONTH = (undef, qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec));
my @DAY_OF_WEEK = (undef, qw(Mon Tue Wed Thu Fri Sat Sun));

my $STATUS_TIMEZONE = DateTime::TimeZone->new( name => 'local');
my @OUTPUT_FIELDS = (
    qw(id created_at text in_reply_to_screen_name),
    (map {"user/$_"} qw(screen_name name profile_image_url)),
    (map {"busybird/$_"} qw(input_name)),
);

sub new {
    my ($class) = @_;
    return bless {
        datetime => undef,
        scores => {},
        output => {
            map {$_ => undef} @OUTPUT_FIELDS,
        },
    }, $class;
}

sub _getOutputObject {
    my ($self, %params) = @_;
    my $output_obj = {};
    while(my ($output_key, $output_val) = each(%{$self->{output}})) {
        my @paths = split("/", $output_key);
        my $cur_ref = $output_obj;
        while(int(@paths) > 0) {
            my $path = shift(@paths);
            if(int(@paths) == 0) {
                $cur_ref->{$path} = $output_val;
            }else {
                $cur_ref->{$path} = {} if !defined($cur_ref->{$path});
                $cur_ref = $cur_ref->{$path};
            }
        }
    }
    $output_obj->{busybird}->{is_new} = $params{is_new};
    if(defined($params{output_name}) && defined($self->{scores}->{$params{output_name}})) {
        $output_obj->{busybird}->{score} = $self->{scores}->{$params{output_name}};
    }
    return $output_obj;
}

sub setTimeZone {
    my ($class, $timezone_str) = @_;
    $STATUS_TIMEZONE = DateTime::TimeZone->new(name => $timezone_str);
}

sub setDateTime {
    my ($self, $datetime) = @_;
    $datetime = DateTime->now if !defined($datetime);
    $datetime->set_time_zone($STATUS_TIMEZONE);
    $self->{datetime} = $datetime;
    $self->{output}->{created_at} = sprintf("%s %s %s",
                                            $DAY_OF_WEEK[$datetime->day_of_week],
                                            $MONTH[$datetime->month],
                                            $datetime->strftime('%e %H:%M:%S %z %Y'))
}

sub getDateTime {
    my ($self) = @_;
    return $self->{datetime};
}

sub setInputName {
    my ($self, $input_name) = @_;
    $self->set('busybird/input_name', $input_name);
}

sub getInputName {
    my ($self) = @_;
    return $self->get('busybird/input_name');
}

sub getID {
    my ($self) = @_;
    return $self->get('id');
}

sub set {
    my ($self, %key_vals) = @_;
    while(my ($key, $val) = each(%key_vals)) {
        die "No field in Status named $key" if !exists($self->{output}->{$key});
        $self->{output}->{$key} = $val;
    }
}

sub get {
    my ($self, @keys) = @_;
    my @ret = ();
    foreach my $key (@keys) {
        die "No field in Status named $key" if !exists($self->{output}->{$key});
        push(@ret, $self->{output}->{$key});
    }
    return wantarray ? @ret : $ret[0];
}

## sub set {
##     my ($self, $val, @param_path) = @_;
##     my $output_ref = $self->{output};
##     foreach my $path_elem (@param_path) {
##         die "Seek path elem $path_elem in non-hash element" if ref($output_ref) ne 'HASH';
##         die "Seek path elem $path_elem but not found" if !exists($output_ref->{$path_elem});
##     }
## }

sub getJSON {
    my ($self, %params) = @_;
    return encode_json($self->_getOutputObject(%params));
    ## my $obj = {
    ##     bb_input_name => $self->getInputName,
    ##     bb_datetime => $self->getDateTime->strftime('%Y/%m/%dT%H:%M:%S%z'),
    ##     id => $self->getID,
    ##     created_at => sprintf("%s %s %s",
    ##                           $DAY_OF_WEEK[$self->getDateTime->day_of_week],
    ##                           $MONTH[$self->getDateTime->month],
    ##                           $self->getDateTime->strftime('%e %H:%M:%S %z %Y')),
    ##     text => $self->getText,
    ##     user => {
    ##         screen_name => $self->getSourceName,
    ##         name => $self->getSourceNameAlt,
    ##         profile_image_url => $self->getIconURL,
    ##     },
    ##     in_reply_to_screen_name => $self->getReplyToName,
    ## };
    ## return encode_json($obj);
}

1;


