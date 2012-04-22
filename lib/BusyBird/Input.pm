package BusyBird::Input;
use base 'BusyBird::Object';

use strict;
use warnings;
use Scalar::Util ('blessed');
use DateTime;
use IO::File;
## use POE;
## use BusyBird::CallStack;

use AnyEvent;
use BusyBird::Log ('bblog');
use BusyBird::Filter;

my $DEFAULT_PAGE_COUNT = 100;
my $DEFAULT_PAGE_MAX   = 10;
my $DEFAULT_PAGE_NO_THRESHOLD_MAX = 1;
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
        $self->_loadTimeFile();
    };
    if($@) {
        &bblog("WARNING: $@Time file is not loaded.");
    }
    ## POE::Session->create(
    ##     object_states => [
    ##         $self => {
    ##             _start => '_sessionStart',
    ##             on_get_statuses => '_sessionOnGetStatuses',
    ##         },
    ##     ],
    ##     inline_states => {
    ##         _stop => sub {
    ##             ;
    ##         },
    ##     },
    ## );
    return $self;
}

sub _setParams {
    my ($self, $params_ref) = @_;
    $self->_setParam($params_ref, 'name', undef, 1);
    $self->_setParam($params_ref, 'no_timefile', 0);
    $self->_setParam($params_ref, 'page_count', $DEFAULT_PAGE_COUNT);
    $self->_setParam($params_ref, 'page_max', $DEFAULT_PAGE_MAX);
    $self->_setParam($params_ref, 'page_no_threshold_max', $DEFAULT_PAGE_NO_THRESHOLD_MAX);
    $self->{last_status_epoch_time} = undef;
    $self->{page_no_threshold_max} = $self->{page_max} if $self->{page_no_threshold_max} > $self->{page_max};
    $self->{on_get_statuses} = [];
    $self->{filter} = BusyBird::Filter->new();
}

sub getFilter {
    my $self = shift;
    return $self->{filter};
}

sub listenOnGetStatuses {
    my ($self, $callback) = @_;
    push(@{$self->{on_get_statuses}}, $callback);
        
}

sub _emitOnGetStatuses {
    my ($self, $statuses) = @_;
    $self->getFilter->execute(
        $statuses,
        sub {
            my ($filtered_statuses) = @_;
            if(defined($filtered_statuses) and @$filtered_statuses) {
                $_->($filtered_statuses) foreach @{$self->{on_get_statuses}};
            }
        },
    );
}

## sub _sessionStart {
##     my ($self, $session, $kernel) = @_[OBJECT, SESSION, KERNEL];
##     $self->{session} = $session->ID;
##     $kernel->alias_set($self->{session});
## }

sub _getStatusesPage {
    my ($self, $count, $page, $callback) = @_;
    die sprintf("%s does not support polling.", ref($self));
    
    ## ** MUST BE IMPLEMENTED BY SUBCLASSES
    ## my ($self, $callstack, $ret_session, $ret_event, $count, $page) = @_;
    ## POE::Kernel->post($ret_session, $ret_event, $callstack, undef);
}

sub _getTimeFilePath {
    my ($self) = @_;
    return "busybird_" . $self->{name} . ".time";
}

## synchronous...
sub _loadTimeFile {
    my ($self) = @_;
    return if $self->{no_timefile};
    my $filepath = $self->_getTimeFilePath();
    my $file = IO::File->new();
    if(!$file->open($filepath, "r")) {
        die "Cannot open $filepath to read";
    }
    my $epoch_time = $file->getline();
    if(!defined($epoch_time)) {
        $file->close();
        die "Invalid time file $filepath";
    }
    chomp $epoch_time;
    $self->{last_status_epoch_time} = int($epoch_time) - $THRESHOLD_OFFSET_SEC;
    $file->close();
}

## synchronous...
sub _saveTimeFile {
    my ($self) = @_;
    return if $self->{no_timefile};
    my $filepath = $self->_getTimeFilePath();
    my $file = IO::File->new();
    if(!$file->open($filepath, "w")) {
        die "Cannot open $filepath to write to.";
    }
    $file->printf("%s\n", (defined($self->{last_status_epoch_time}) ? $self->{last_status_epoch_time} : "null"));
    $file->close();
}

sub getStatuses {
    my ($self, $threshold_epoch_time) = @_;
    my $page = 0;
    my $ret_array = [];
    $threshold_epoch_time = $self->{last_status_epoch_time} if !defined($threshold_epoch_time);
    my $callback;
    my $load_page_max = defined($threshold_epoch_time) ? $self->{page_max} : $self->{page_no_threshold_max};
    $callback = sub {
        my ($statuses) = @_;
        &bblog("Input::_sessionOnGetStatuses");
        my $is_complete = 0;
        if(!defined($statuses) || int(@$statuses) == 0) {
            $is_complete = 1;
        }else {
            foreach my $status (@$statuses) {
                my $datetime = $status->getDateTime();
                ## ** Update latest status time
                if (!defined($self->{last_status_epoch_time}) || $datetime->epoch > $self->{last_status_epoch_time}) {
                    $self->{last_status_epoch_time} = $datetime->epoch;
                }
                ## ** Collect new status
                if (!defined($threshold_epoch_time) || $datetime->epoch >= $threshold_epoch_time) {
                    $status->setInputName($self->{name});
                    push(@{$ret_array}, $status);
                } else {
                    $is_complete = 1;
                }
            }
        }
        $page++;
        if($is_complete || $page == $load_page_max) {
            if($page == $self->{page_max} && !$is_complete && defined($threshold_epoch_time)) {
                &bblog("WARNING: page has reached the max value of ".$self->{page_max});
            }
            $self->_saveTimeFile();
            if(@$ret_array) {
                $self->_emitOnGetStatuses($ret_array);
            }
        }else {
            $self->_getStatusesPage($self->{page_count}, $page, $callback);
        }        
    };
    $self->_getStatusesPage($self->{page_count}, $page, $callback);

    ## my ($self, $callstack, $callback_session, $callback_event, $threshold_epoch_time) = @_;
    ## my $page = 0;
    ## &bblog("Input::getNewStatuses(callback_session => $callback_session, callback_event => $callback_event)");
    ## $callstack = BusyBird::CallStack->newStack($callstack, $callback_session, $callback_event,
    ##                                            threshold_epoch_time =>
    ##                                                defined($threshold_epoch_time) ? $threshold_epoch_time : $self->{last_status_epoch_time},
    ##                                            page => $page,
    ##                                            ret_array => [],
    ##                                        );
    ## $self->_getStatuses($callstack, $self->{session}, 'on_get_statuses', $self->{page_count}, $page);
    ## return;

    #### ################
    #### 
    #### my $ret_array = [];
    #### $threshold_epoch_time = $self->{last_status_epoch_time} if !defined($threshold_epoch_time);
    #### my $page;
    #### for($page = 0 ; $page < $self->{page_max} ; $page++) {
    ####     my $statuses = $self->_getStatuses($self->{page_count}, $page);
    ####     my $is_complete = 0;
    ####     last if !defined($statuses);
    ####     foreach my $status (@$statuses) {
    ####         my $datetime = $status->getDateTime()->clone();
    ####         $datetime->set_time_zone($TIMEZONE);
    ####         ## ** Update latest status time
    ####         if(!defined($self->{last_status_epoch_time}) || $datetime->epoch > $self->{last_status_epoch_time}) {
    ####             $self->{last_status_epoch_time} = $datetime->epoch;
    ####         }
    ####         ## ** Collect new status
    ####         if(!defined($threshold_epoch_time) || $datetime->epoch >= $threshold_epoch_time) {
    ####             $status->setInputName($self->{name});
    ####             push(@$ret_array, $status);
    ####         }else {
    ####             $is_complete = 1;
    ####         }
    ####     }
    ####     if($is_complete || !defined($threshold_epoch_time)) {
    ####         last;
    ####     }
    #### }
    #### if($page == $self->{page_max}) {
    ####     print STDERR ("WARNING: page has reached the max value of ".$self->{page_max}."\n");
    #### }
    #### $self->_saveTimeFile();
    #### return $ret_array;
}

## sub _sessionOnGetStatuses {
##     my ($self, $kernel, $callstack, $statuses) = @_[OBJECT, KERNEL, ARG0 .. ARG1];
##     &bblog("Input::_sessionOnGetStatuses");
##     my $threshold_epoch_time = $callstack->get('threshold_epoch_time');
##     my $page = $callstack->get('page');
##     my $is_complete = 0;
##     if(!defined($statuses) || int(@$statuses) == 0) {
##         $is_complete = 1;
##     }else {
##         foreach my $status (@$statuses) {
##             my $datetime = $status->getDateTime();
##             ## ** Update latest status time
##             if (!defined($self->{last_status_epoch_time}) || $datetime->epoch > $self->{last_status_epoch_time}) {
##                 $self->{last_status_epoch_time} = $datetime->epoch;
##             }
##             ## ** Collect new status
##             if (!defined($threshold_epoch_time) || $datetime->epoch >= $threshold_epoch_time) {
##                 $status->setInputName($self->{name});
##                 push(@{$callstack->get('ret_array')}, $status);
##             } else {
##                 $is_complete = 1;
##             }
##         }
##     }
##     
##     $page++;
##     if($is_complete || !defined($threshold_epoch_time) || $page == $self->{page_max}) {
##         if($page == $self->{page_max} && !$is_complete && defined($threshold_epoch_time)) {
##             &bblog("WARNING: page has reached the max value of ".$self->{page_max});
##         }
##         $self->_saveTimeFile();
##         $callstack->pop($callstack->get('ret_array'));
##     }else {
##         $callstack->set(page => $page);
##         $self->_getStatuses($callstack, $self->{session}, 'on_get_statuses', $self->{page_count}, $page);
##     }
## }

sub getName {
    my ($self) = @_;
    return $self->{name};
}

1;
