package BusyBird::Status;
use strict;
use warnings;
use Carp;
use JSON;
use XML::Simple;
use Storable ('dclone');
use BusyBird::Log qw(bblog);
use Encode;

$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

our $FORMAT_JSON_SORTED = 0;
## our $_STATUS_TIMEZONE = DateTime::TimeZone->new( name => 'local');

sub new {
    my ($class, @args) = @_;
    my $self = bless {
        int(@args) == 1 ? %{$args[0]} : (@args)
    }, $class;
    foreach my $mandatory (qw(created_at id id_str)) {
        if(!defined($self->{$mandatory})) {
            croak "Param $mandatory is mandatory for Status";
        }
    }
    return $self;
}

## sub setTimeZone {
##     my ($class, $timezone_str) = @_;
##     $_STATUS_TIMEZONE = DateTime::TimeZone->new(name => $timezone_str);
## }
## 
## sub getTimeZone {
##     my ($class) = @_;
##     return $_STATUS_TIMEZONE;
## }

## sub content {
##     my $self = shift;
##     return $self->{content};
## }

## sub put {
##     my ($self, %params) = @_;
##     ## @{$self->{content}}{keys %params} = values %params;
##     @{$self}{keys %params} = values %params;
## }

sub clone {
    my ($self) = @_;
    return dclone($self);
}

sub _translateTreeNodes {
    my ($class_self, $root, %translate_rules) = @_;
    my @unvisited_entries = (['_root', \$root]);
    while(my $cur_entry = pop(@unvisited_entries)) {
        my ($label, $cur_ref) = @$cur_entry;
        my $label_key = '.' . $label;
        if(defined($translate_rules{$label_key})) {
            $$cur_ref = $translate_rules{$label_key}->($$cur_ref);
            next;
        }
        if(ref($$cur_ref) eq 'ARRAY') {
            my $i = 0;
            foreach my $ref (@$$cur_ref) {
                push(@unvisited_entries, [$i, \$ref]);
                $i++;
            }
            next;
        }elsif(ref($$cur_ref) eq 'HASH' || ref($$cur_ref) eq 'BusyBird::Status') {
            foreach my $key (keys %$$cur_ref) {
                push(@unvisited_entries, [$key, \$$$cur_ref{$key}]);
            }
            ## while(my ($key, $val) = each()) {
            ##     push(@unvisited_entries, [$key, \$val]);
            ## }
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

## sub _datetimeFormatTwitter {
##     my $dt = shift;
##     $dt->set_time_zone($_STATUS_TIMEZONE) if defined($_STATUS_TIMEZONE);
##     return sprintf("%s %s %s",
##                    $DAY_OF_WEEK[$dt->day_of_week],
##                    $MONTH[$dt->month],
##                    $dt->strftime('%d %H:%M:%S %z %Y'));
## }

sub _XMLFormatEntities {
    my ($entities_ref) = @_;
    return undef if !defined($entities_ref);
    my $root = {};
    foreach my $field_key (keys %$entities_ref) {
        $root->{$field_key} = [];
        ## my $entity_key = substr($field_key, 0, -1);
        foreach my $entity (@{$entities_ref->{$field_key}}) {
            my $translated_entity = {%$entity};
            my ($start, $end) = @{$entity->{indices}};
            __PACKAGE__->_translateTreeNodes(
                $translated_entity,
                _SCALAR_ELEM => sub {
                    my ($scalar) = @_;
                    return {content => $scalar};
                }
            );
            $translated_entity->{start} = $start;
            $translated_entity->{end} = $end;
            delete $translated_entity->{indices};
            push(@{$root->{$field_key}}, $translated_entity);
        }
    }
    return XMLout(
        $root, RootName => undef,
        GroupTags => {
            urls => 'url',
            hashtags => 'hashtag',
            user_mentions => 'user_mention',
            media => 'creative', ## What's going on !!??
        }, NoIndent => 1, SuppressEmpty => undef,
        KeyAttr => ['start', 'end'],
    );
}

sub TO_JSON {
    my ($self) = @_;
    return {%$self}; ## ** Unbless the hash object. That's all!
    ## my $clone = $self->clone();
    ## $clone->_translateTreeNodes(
    ##     $clone,
    ##     'DateTime' => \&_datetimeFormatTwitter,
    ## );
    ## return {%$clone}; ## ** Unbless the hash object
}

my %FORMATTERS = (
    json => sub {
        my ($statuses_ref) = @_;
        ## my @statuses_for_json = map { $_->convertForJSON } @$statuses_ref;
        return to_json(
            ## \@statuses_for_json,
            $statuses_ref,
            {canonical => $FORMAT_JSON_SORTED,
             ascii => 1, allow_blessed => 1, convert_blessed => 1}
        );
    },
    xml => sub {
        my ($statuses_ref) = @_;
        my @xml_entries = ();
        foreach my $status (@$statuses_ref) {
            my $clone = $status->clone();
            $clone->_translateTreeNodes(
                ## $clone->content,
                $clone,
                ## 'DateTime' => \&_datetimeFormatTwitter,
                '.entities' => \&_XMLFormatEntities,
                '_SCALAR_ELEM' => sub {
                    my $scalar = shift;
                    return undef if !defined($scalar);
                    $scalar =~ s|&|&amp;|g;
                    $scalar =~ s|<|&lt;|g;
                    $scalar =~ s|>|&gt;|g;
                    $scalar =~ s|'|&quot;|g;
                    return $scalar;
                }
            );
            push(@xml_entries, XMLout(
                ## $clone->content,
                $clone,
                NoAttr => 1, RootName => 'status',
                SuppressEmpty => undef, KeyAttr => [], NoEscape => 1, NoIndent => 1,
            ));
        }
        return qq(<statuses type="array">) . Encode::encode('utf8', join("", @xml_entries)) . qq(</statuses>);
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
    ## local $_STATUS_TIMEZONE = undef;
    return $class->format('json', $statuses_ref);
}

sub deserialize {
    my ($class, $string) = @_;
    my $raw_statuses = decode_json($string);
    if(ref($raw_statuses) ne 'ARRAY') {
        $raw_statuses = [$raw_statuses];
    }
    my @statuses = ();
    @statuses = map {BusyBird::Status->new($_)} @$raw_statuses;
    return \@statuses;
    ## foreach my $raw_status (@$raw_statuses) {
    ##     $class->_translateTreeNodes(
    ##         $raw_status,
    ##         _SCALAR_ELEM => sub {
    ##             my ($elem_orig) = @_;
    ##             if(!defined($elem_orig)) {
    ##                 return $elem_orig;
    ##             }
    ##             my $elem = $elem_orig;
    ##             my ($dow, $month_str, $dom, $h, $m, $s, $tz_str, $year) = ($elem =~ $DATETIME_STR_MATCHER);
    ##             if($dow) {
    ##                 return DateTime->new(
    ##                     year      => $year,
    ##                     month     => $MONTH_FROM_STR{$month_str},
    ##                     day       => $dom,
    ##                     hour      => $h,
    ##                     minute    => $m,
    ##                     second    => $s,
    ##                     time_zone => $tz_str,
    ##                 );
    ##             }
    ##             return $elem_orig;
    ##         },
    ##     );
    ##     push(@statuses, BusyBird::Status->new($raw_status));
    ## }
    ## return \@statuses;
}

1;


