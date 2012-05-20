package BusyBird::Status;
use strict;
use warnings;
use JSON;
use XML::Simple;
use Storable ('dclone');
use DateTime;
use BusyBird::Log qw(bblog);

my @MONTH = (undef, qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec));
my @DAY_OF_WEEK = (undef, qw(Mon Tue Wed Thu Fri Sat Sun));


my $STATUS_TIMEZONE = DateTime::TimeZone->new( name => 'local');

sub new {
    my ($class, %params) = @_;
    my $self = bless {
        content => { %params }
    }, $class;
    foreach my $mandatory (qw(created_at id id_str)) {
        if(!defined($self->content->{$mandatory})) {
            die "Param $mandatory is mandatory for Status";
        }
    }
    return $self;
}

sub setTimeZone {
    my ($class, $timezone_str) = @_;
    $STATUS_TIMEZONE = DateTime::TimeZone->new(name => $timezone_str);
}

sub getTimeZone {
    my ($class) = @_;
    return $STATUS_TIMEZONE;
}

sub content {
    my $self = shift;
    return $self->{content};
}

sub put {
    my ($self, %params) = @_;
    @{$self->{content}}{keys %params} = values %params;
}

sub clone {
    my ($self) = @_;
    return dclone($self);
}

sub _formatElements {
    my ($self, %formatters) = @_;
    my $content = $self->content;
    my @unvisited_ref = (\$content);
    while(my $cur_ref = pop(@unvisited_ref)) {
        if(ref($$cur_ref) eq 'ARRAY') {
            push(@unvisited_ref, \$_) foreach @$$cur_ref;
            next;
        }elsif(ref($$cur_ref) eq 'HASH') {
            push(@unvisited_ref, \$_) foreach values %$$cur_ref;
            next;
        }elsif(!ref($$cur_ref)) {
            next;
        }
        my @matched_class = grep { $$cur_ref->isa($_) } keys %formatters;
        if(@matched_class) {
            $$cur_ref = $formatters{$matched_class[0]}->($$cur_ref);
        }
    }
}

sub _datetimeFormatTwitter {
    my $dt = shift;
    $dt->set_time_zone($STATUS_TIMEZONE);
    return sprintf("%s %s %s",
                   $DAY_OF_WEEK[$dt->day_of_week],
                   $MONTH[$dt->month],
                   $dt->strftime('%e %H:%M:%S %z %Y'));
}

my %FORMATTERS = (
    json => sub {
        my ($statuses_ref) = @_;
        my @json_entries = ();
        foreach my $status (@$statuses_ref) {
            my $clone = $status->clone();
            $clone->_formatElements(
                'DateTime' => \&_datetimeFormatTwitter,
            );
            push(@json_entries, to_json($clone->content));
        }
        return '[' . join(",", @json_entries) . ']';
    },
    xml => sub {
        my ($statuses_ref) = @_;
        my @xml_entries = ();
        foreach my $status (@$statuses_ref) {
            my $clone = $status->clone();
            $clone->_formatElements(
                'DateTime' => \&_datetimeFormatTwitter,
            );
            push(@xml_entries, XMLout($clone->content, NoAttr => 1, RootName => 'status', SuppressEmpty => undef));
        }
        return qq(<statuses type="array">\n) . join("", @xml_entries) . qq(</statuses>\n);
    },
);

my %MIMES = (
    json => 'application/json; charset=UTF-8',
    xml => 'application/xml',
);

sub format {
    my ($class, $format, $statuses_ref) = @_;
    $format ||= 'json';
    if(!defined($FORMATTERS{$format})) {
        &bblog(sprintf("%s: No such format as $format", __PACKAGE__));
        return undef;
    }
    return $FORMATTERS{$format}->($statuses_ref);
}

sub mime {
    my ($class, $format) = @_;
    $format ||= 'json';
    if(!defined($MIMES{$format})) {
        &bblog(sprintf("%s: No such format as $format", __PACKAGE__));
        return undef;
    }
    return $MIMES{$format};
}

1;


