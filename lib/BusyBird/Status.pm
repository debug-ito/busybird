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
## my @OUTPUT_FIELDS = (
##     qw(id created_at text in_reply_to_screen_name),
##     (map {"user/$_"} qw(screen_name name profile_image_url)),
##     (map {"busybird/$_"} qw(input_name)),
## );

sub new {
    my ($class, %params) = @_;
    my $self = bless {
        content => { %params }
    }, $class;
    foreach my $mandatory (qw(created_at id)) {
        if(!defined($self->content->{$mandatory})) {
            die "Param $mandatory is mandatory for Status";
        }
    }
    if(!defined($self->content->{id_str})) {
        $self->content->{id_str} = sprintf("%s", $self->content->{id});
    }
    return $self;
}

## sub _getOutputObject [[must be checked...]] {
##     my ($self, %params) = @_;
##     my $output_obj = {};
##     while(my ($output_key, $output_val) = each(%{$self->{output}})) {
##         my @paths = split("/", $output_key);
##         my $cur_ref = $output_obj;
##         while(int(@paths) > 0) {
##             my $path = shift(@paths);
##             if(int(@paths) == 0) {
##                 $cur_ref->{$path} = $output_val;
##             }else {
##                 $cur_ref->{$path} = {} if !defined($cur_ref->{$path});
##                 $cur_ref = $cur_ref->{$path};
##             }
##         }
##     }
##     $output_obj->{busybird}->{is_new} = $params{is_new};
##     if(defined($params{output_name}) && defined($self->{scores}->{$params{output_name}})) {
##         $output_obj->{busybird}->{score} = $self->{scores}->{$params{output_name}};
##     }
##     return $output_obj;
## }

sub setTimeZone {
    my ($class, $timezone_str) = @_;
    $STATUS_TIMEZONE = DateTime::TimeZone->new(name => $timezone_str);
}

sub getTimeZone {
    my ($class) = @_;
    return $STATUS_TIMEZONE;
}

## sub setDateTime {
##     my ($self, $datetime) = @_;
##     $datetime = DateTime->now if !defined($datetime);
##     $datetime->set_time_zone($STATUS_TIMEZONE);
##     $self->{datetime} = $datetime;
##     $self->content->{created_at} =
##         sprintf("%s %s %s",
##                 $DAY_OF_WEEK[$datetime->day_of_week],
##                 $MONTH[$datetime->month],
##                 $datetime->strftime('%e %H:%M:%S %z %Y'));
## }
## 
## sub getDateTime {
##     my ($self) = @_;
##     return $self->{datetime};
## }
## 
## sub setInputName {
##     my ($self, $input_name) = @_;
##     ## $self->set('busybird/input_name', $input_name);
##     $self->content->{busybird}->{input_name} = $input_name;
## }
## 
## sub getInputName {
##     my ($self) = @_;
##     ## return $self->get('busybird/input_name');
##     return $self->content->{busybird}->{input_name};
## }
## 
## sub getID {
##     my ($self) = @_;
##     ## return $self->get('id');
##     $self->content->{id};
## }
## 

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

## sub _find {
##     my ($self, $key, $do_create_nodes) = @_;
##     my @paths = split("/", $key);
##     my $cur_ref = $self->{output};
##     while(int(@paths) > 0) {
##         my $path = shift(@paths);
##         if(int(@paths) == 0) {
##             if($do_create_nodes && !exists($cur_ref->{$path})) {
##                 $cur_ref->{$path} = undef;
##             }
##             return \ {$cur_ref->{$path}};
##         }else {
##             $cur_ref->{$path} = {} if !defined($cur_ref->{$path});
##             if(!ref($cur_ref->{$path})) {
##                 die "$path is a leaf node and $key tries to descend from it.";
##             }
##             $cur_ref = $cur_ref->{$path};
##         }
##     }    
## }

## sub _makeDerefString {
##     my ($class_self, $key) = @_;
##     return join "->", map { "{'$_'}" } ('output', split('/', $key));
## }
## 
## sub set {
##     my ($self, %key_vals) = @_;
##     while(my ($key, $val) = each(%key_vals)) {
##         die "Value for $key is a reference, which is not allowed." if ref($val);
##         my $deref_str = $self->_makeDerefString($key);
##         eval qq{\$self->$deref_str = \$val};
##         ## my @paths = split("/", $key);
##         ## my $cur_ref = $self->{output};
##         ## while(int(@paths) > 0) {
##         ##     my $path = shift(@paths);
##         ##     if(int(@paths) == 0) {
##         ##         if(ref($cur_ref)) {
##         ##             die "$key is a non-leaf node in output.";
##         ##         }
##         ##         $cur_ref->{$path} = $val;
##         ##     }else {
##         ##         $cur_ref->{$path} = {} if !defined($cur_ref->{$path});
##         ##         if(!ref($cur_ref->{$path})) {
##         ##             die "$path is a leaf node and $key tries to descend from it.";
##         ##         }
##         ##         $cur_ref = $cur_ref->{$path};
##         ##     }
##         ## }
##     }
## }
## 
## sub get {
##     my ($self, @keys) = @_;
##     my @ret = ();
##     foreach my $key (@keys) {
##         die "No field in Status named $key" if !exists($self->{output}->{$key});
##         push(@ret, $self->{output}->{$key});
##     }
##     return wantarray ? @ret : $ret[0];
## }

## sub set {
##     my ($self, $val, @param_path) = @_;
##     my $output_ref = $self->{output};
##     foreach my $path_elem (@param_path) {
##         die "Seek path elem $path_elem in non-hash element" if ref($output_ref) ne 'HASH';
##         die "Seek path elem $path_elem but not found" if !exists($output_ref->{$path_elem});
##     }
## }

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


