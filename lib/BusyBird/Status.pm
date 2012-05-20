package BusyBird::Status;
use strict;
use warnings;
use JSON;
use XML::Simple;
use Storable ('dclone');
use DateTime;
use BusyBird::Log qw(bblog);

my @MONTH = (undef, qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec));
my %MONTH_FROM_STR = ( map { $MONTH[$_] => $_ } 1..12);
my @DAY_OF_WEEK = (undef, qw(Mon Tue Wed Thu Fri Sat Sun));

my $DATETIME_STR_MATCHER;
{
    my $month_selector = join('|', @MONTH[1..12]);
    my $dow_selector = join('|', @DAY_OF_WEEK[1..7]);
    $DATETIME_STR_MATCHER = qr!^($dow_selector) +($month_selector) +(\d{2}) +(\d{2}):(\d{2}):(\d{2}) +([\-\+]\d{4}) +(\d+)$!;
}


our $_STATUS_TIMEZONE = DateTime::TimeZone->new( name => 'local');

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
    $_STATUS_TIMEZONE = DateTime::TimeZone->new(name => $timezone_str);
}

sub getTimeZone {
    my ($class) = @_;
    return $_STATUS_TIMEZONE;
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

sub _translateTreeNodes {
    my ($class_self, $root, %translate_rules) = @_;
    my @unvisited_ref = (\$root);
    while(my $cur_ref = pop(@unvisited_ref)) {
        if(ref($$cur_ref) eq 'ARRAY') {
            push(@unvisited_ref, \$_) foreach @$$cur_ref;
            next;
        }elsif(ref($$cur_ref) eq 'HASH') {
            push(@unvisited_ref, \$_) foreach values %$$cur_ref;
            next;
        }elsif(!ref($$cur_ref)) {
            if(defined($translate_rules{_SCALAR_ELEM})) {
                $$cur_ref = $translate_rules{_SCALAR_ELEM}->($$cur_ref);
            }
            next;
        }
        my @matched_class = grep { $$cur_ref->isa($_) } keys %translate_rules;
        if(@matched_class) {
            $$cur_ref = $translate_rules{$matched_class[0]}->($$cur_ref);
        }
    }
}

sub _datetimeFormatTwitter {
    my $dt = shift;
    $dt->set_time_zone($_STATUS_TIMEZONE) if defined($_STATUS_TIMEZONE);
    return sprintf("%s %s %s",
                   $DAY_OF_WEEK[$dt->day_of_week],
                   $MONTH[$dt->month],
                   $dt->strftime('%d %H:%M:%S %z %Y'));
}

my %FORMATTERS = (
    json => sub {
        my ($statuses_ref) = @_;
        my @json_entries = ();
        foreach my $status (@$statuses_ref) {
            my $clone = $status->clone();
            $clone->_translateTreeNodes(
                $clone->content,
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
            $clone->_translateTreeNodes(
                $clone->content,
                'DateTime' => \&_datetimeFormatTwitter,
            );
            push(@xml_entries, XMLout($clone->content, NoAttr => 1, RootName => 'status', SuppressEmpty => undef, KeyAttr => []));
        }
        return qq(<statuses type="array">) . join("", @xml_entries) . qq(</statuses>\n);
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

sub serialize {
    my ($class, $statuses_ref) = @_;
    local $_STATUS_TIMEZONE = undef;
    return $class->format('json', $statuses_ref);
}

sub deserialize {
    my ($class, $string) = @_;
    my $raw_statuses = from_json($string);
    if(ref($raw_statuses) ne 'ARRAY') {
        $raw_statuses = [$raw_statuses];
    }
    my @statuses = ();
    foreach my $raw_status (@$raw_statuses) {
        $class->_translateTreeNodes(
            $raw_status,
            _SCALAR_ELEM => sub {
                my ($elem) = @_;
                if(!defined($elem)) {
                    return $elem;
                }
                my ($dow, $month_str, $dom, $h, $m, $s, $tz_str, $year) = ($elem =~ $DATETIME_STR_MATCHER);
                if($dow) {
                    return DateTime->new(
                        year      => $year,
                        month     => $MONTH_FROM_STR{$month_str},
                        day       => $dom,
                        hour      => $h,
                        minute    => $m,
                        second    => $s,
                        time_zone => $tz_str,
                    );
                }
                return $elem;
            },
        );
        my $status;
        eval {
            $status = BusyBird::Status->new(%$raw_status);
        };
        if($@) {
            &bblog("Failed to deserialize a status. Skip: $@");
            next;
        }
        push(@statuses, $status);
    }
    return \@statuses;
}

1;


