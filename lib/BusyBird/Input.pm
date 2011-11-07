package BusyBird::Input;

use strict;
use warnings;
use Scalar::Util ('blessed');
use DateTime;
use IO::File;

my $DEFAULT_PAGE_COUNT = 100;
my $DEFAULT_PAGE_MAX   = 10;
my $ID_CACHE_MAX = 100;

my $TIMEZONE = DateTime::TimeZone->new(name => 'local');

my $THRESHOLD_OFFSET_SEC = 0;

sub setThresholdOffset {
    my ($class, $offset) = @_;
    $THRESHOLD_OFFSET_SEC = $offset;
}

sub new {
    my ($class, %params) = @_;
    my $self = bless {}, $class;
    $self->_setParams(\%params);
    eval {
        $self->_loadCacheFile();
    };
    if($@) {
        print STDERR "WARNING: $@Cache is not loaded.\n";
    }
    return $self;
}

sub _setParam {
    my ($self, $params_ref, $key, $default, $is_mandatory) = @_;
    if($is_mandatory && !defined($params_ref->{$key})) {
        my $classname = blessed $self;
        die "ERROR: _setParam in $classname: Parameter for '$key' is mandatory, but not supplied.";
    }
    $self->{$key} = (defined($params_ref->{$key}) ? $params_ref->{$key} : $default);
}

sub _setParams {
    my ($self, $params_ref) = @_;
    $self->_setParam($params_ref, 'name', undef, 1);
    $self->_setParam($params_ref, 'last_status_epoch_time');
    $self->_setParam($params_ref, 'page_count', $DEFAULT_PAGE_COUNT);
    $self->_setParam($params_ref, 'page_max', $DEFAULT_PAGE_MAX);
}

sub _getStatuses {
    ## ** MUST BE IMPLEMENTED BY SUBCLASSES
    my ($self, $count, $page) = @_;
    return undef;
}

sub _getCacheFilePath {
    my ($self) = @_;
    return "busybird_" . $self->{name} . ".time";
}

sub _loadCacheFile {
    my ($self) = @_;
    my $filepath = $self->_getCacheFilePath();
    my $file = IO::File->new();
    if(!$file->open($filepath, "r")) {
        die "Cannot open $filepath to read";
    }
    my $epoch_time = $file->getline();
    if(!defined($epoch_time)) {
        $file->close();
        die "Invalid cache file $filepath";
    }
    chomp $epoch_time;
    $self->{last_status_epoch_time} = int($epoch_time) - $THRESHOLD_OFFSET_SEC;
    ## while(my $line = $file->getline()) {
    ##     chomp $line;
    ##     $self->{latest_id_cache}{$line} = 1;
    ## }
    $file->close();
}

sub _saveCacheFile {
    my ($self) = @_;
    my $filepath = $self->_getCacheFilePath();
    my $file = IO::File->new();
    if(!$file->open($filepath, "w")) {
        die "Cannot open $filepath to write to.";
    }
    $file->printf("%s\n", (defined($self->{last_status_epoch_time}) ? $self->{last_status_epoch_time} : "null"));
    ## foreach my $id (keys(%{$self->{latest_id_cache}})) {
    ##     $file->print("$id\n");
    ## }
    $file->close();
}

sub getNewStatuses {
    my ($self, $threshold_epoch_time) = @_;
    my $ret_array = [];
    $threshold_epoch_time = $self->{last_status_epoch_time} if !defined($threshold_epoch_time);
    for(my $page = 0 ; $page < $self->{page_max} ; $page++) {
        my $statuses = $self->_getStatuses($self->{page_count}, $page);
        my $is_complete = 0;
        last if !defined($statuses);
        foreach my $status (@$statuses) {
            my $datetime = $status->{bb_datetime};
            $datetime->set_time_zone($TIMEZONE);
            ## ** Update latest status time
            if(!defined($self->{last_status_epoch_time}) || $datetime->epoch > $self->{last_status_epoch_time}) {
                $self->{last_status_epoch_time} = $datetime->epoch;
            }
            ## ** Collect new status
            if(!defined($threshold_epoch_time) || $datetime->epoch >= $threshold_epoch_time) {
                $status->{bb_input_name} = $self->{name};
                push(@$ret_array, $status);
            }else {
                $is_complete = 1;
            }
        }
        if($is_complete || !defined($threshold_epoch_time)) {
            $self->_saveCacheFile();
            return $ret_array;
        }
    }
    print STDERR ("WARNING: page has reached the max value of ".$self->{page_max}."\n");
    $self->_saveCacheFile();
    return $ret_array;
}

sub getName {
    my ($self) = @_;
    return $self->{name};
}

1;
