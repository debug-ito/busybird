package BusyBird::Input;
use base ('BusyBird::Connector');

use strict;
use warnings;
use DateTime;
use IO::File;
use Module::Load;
use Carp;

use AnyEvent;
use BusyBird::Log ('bblog');
use BusyBird::Filter;
use BusyBird::ComponentManager;
use BusyBird::Util ('setParam');

my $DEFAULT_PAGE_COUNT = 100;
my $DEFAULT_PAGE_MAX   = 10;
my $DEFAULT_PAGE_NO_THRESHOLD_MAX = 1;
my $DEFAULT_PAGE_NEXT_DELAY = 0.2;
my $THRESHOLD_OFFSET_SEC = 0;

sub setThresholdOffset {
    my ($class, $offset) = @_;
    $THRESHOLD_OFFSET_SEC = $offset;
}

sub new {
    my ($class, %params) = @_;
    push(local @BusyBird::Util::CARP_NOT, __PACKAGE__);
    my $self = bless {}, $class;
    $self->_setParams(\%params);
    BusyBird::ComponentManager->register('input', $self);
    $params{busybird_input} = $self;
    load $self->{driver};
    $self->{driver} = $self->{driver}->new(%params);
    return $self;
}

sub _setParams {
    my ($self, $params_ref) = @_;
    $self->setParam($params_ref, 'name', undef, 1);
    $self->setParam($params_ref, 'driver', undef, 1);
    $self->setParam($params_ref, 'no_timefile', 0);
    $self->setParam($params_ref, 'page_count', $DEFAULT_PAGE_COUNT);
    $self->setParam($params_ref, 'page_max', $DEFAULT_PAGE_MAX);
    $self->setParam($params_ref, 'page_no_threshold_max', $DEFAULT_PAGE_NO_THRESHOLD_MAX);
    $self->setParam($params_ref, 'page_next_delay', $DEFAULT_PAGE_NEXT_DELAY);
    $self->{last_status_epoch_time} = undef;
    $self->{page_no_threshold_max} = $self->{page_max} if $self->{page_no_threshold_max} > $self->{page_max};
    $self->{on_get_statuses} = [];
    $self->{filter} = BusyBird::Filter->new();
    $self->{status_loader} = $self->_initLoader();
}

sub getFilter {
    my $self = shift;
    return $self->{filter};
}

sub listenOnGetStatuses {
    my ($self, $callback) = @_;
    push(@{$self->{on_get_statuses}}, $callback);
        
}

sub _uniqStatuses {
    my ($class_self, $statuses) = @_;
    return undef if !defined($statuses);
    my @uniqs = ();
    return \@uniqs if !@$statuses;

    my %ids = ();
    foreach my $status (@$statuses) {
        if(!defined($ids{$status->{id}})) {
            $ids{$status->{id}} = 1;
            push(@uniqs, $status);
        }
    }
    return \@uniqs;
}

sub emitOnGetStatuses {
    my ($self, $statuses) = @_;
    $statuses = $self->_uniqStatuses($statuses);
    $self->getFilter->execute(
        $statuses,
        sub {
            my ($filtered_statuses) = @_;
            if(!defined($filtered_statuses)) {
                &bblog('Input::emitOnGetStatuses: filter output is undef. Use [] instead.');
                $filtered_statuses = [];
            }
            $_->($filtered_statuses) foreach @{$self->{on_get_statuses}};
            ## $self->_getStatusesTriggerDone();
        },
    );
}

sub _getTimeFilePath {
    my ($self) = @_;
    return "bbinput_" . $self->{name} . ".time";
}

## synchronous...
sub loadTimeFile {
    my ($self, $force) = @_;
    return if $self->{no_timefile} && !$force;
    my $filepath = $self->_getTimeFilePath();
    my $file = IO::File->new();
    if(!$file->open($filepath, "r")) {
        croak "Cannot open $filepath to read";
    }
    my $epoch_time = $file->getline();
    if(!defined($epoch_time)) {
        $file->close();
        croak "Invalid time file $filepath";
    }
    $epoch_time =~ s/[ \t\r\n]+$//;
    if($epoch_time =~ /^\d+$/) {
        $self->{last_status_epoch_time} = int($epoch_time) - $THRESHOLD_OFFSET_SEC;
        &bblog("Input " . $self->getName() . ": time file is loaded from $filepath.");
    }else {
        $self->{last_status_epoch_time} = undef;
        &bblog("Input " . $self->getName() . ": time file is loaded but no timestamp is there.");
    }
    $file->close();
}

## synchronous...
sub saveTimeFile {
    my ($self, $force) = @_;
    return if $self->{no_timefile} && !$force;
    my $filepath = $self->_getTimeFilePath();
    my $file = IO::File->new();
    if(!$file->open($filepath, "w")) {
        croak "Cannot open $filepath to write to.";
    }
    $file->printf("%s\n", (defined($self->{last_status_epoch_time}) ? $self->{last_status_epoch_time} : "null"));
    $file->close();
}

sub getStatuses {
    my ($self, $threshold_epoch_time) = @_;

    ## ** status_loader is in charge of loading statuses. It manages job queue.
    $self->{status_loader}->execute(
        $threshold_epoch_time,
        sub {
            my $result_statuses = shift;
            $self->emitOnGetStatuses($result_statuses);
        }
    );
}

sub _initLoader {
    my ($self) = @_;
    my $loader = BusyBird::Filter->new(delay => $self->{page_next_delay});
    $loader->push(
        sub {
            my ($threshold_epoch_time, $done) = @_;
            my $page = 0;
            my $ret_array = [];
            $threshold_epoch_time = $self->{last_status_epoch_time} if !defined($threshold_epoch_time);
            my $callback;
            my $load_page_max = defined($threshold_epoch_time) ? $self->{page_max} : $self->{page_no_threshold_max};
            &bblog(sprintf("Input %s: getStatuses triggerred.", $self->getName));
            $callback = sub {
                my ($statuses) = @_;
                my $is_complete = 0;
                if(!defined($statuses) || int(@$statuses) == 0) {
                    &bblog(sprintf("Input %s: get page %d [0 statuses]", $self->getName, $page));
                    $is_complete = 1;
                }else {
                    &bblog(sprintf("Input %s: get page %d [%d statuses]", $self->getName, $page, int(@$statuses)));
                    foreach my $status (@$statuses) {
                        my $datetime = $status->{created_at};
                        ## ** Update latest status time
                        if (!defined($self->{last_status_epoch_time}) || $datetime->epoch > $self->{last_status_epoch_time}) {
                            $self->{last_status_epoch_time} = $datetime->epoch;
                        }
                        ## ** Collect new status
                        if (!defined($threshold_epoch_time) || $datetime->epoch >= $threshold_epoch_time) {
                            ## $status->setInputName($self->{name});
                            $status->{busybird}->{input_name} = $self->{name};
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
                    $self->saveTimeFile();
                    $done->($ret_array);
                }else {
                    my $tw; $tw = AnyEvent->timer(
                        after => $self->{page_next_delay},
                        cb => sub {
                            undef $tw;
                            ## $self->_getStatusesPage($self->{page_count}, $page, $callback);
                            $self->{driver}->getStatusesPage($self->{page_count}, $page, $callback);
                        },
                    );
                }        
            };
            ## $self->_getStatusesPage($self->{page_count}, $page, $callback);
            $self->{driver}->getStatusesPage($self->{page_count}, $page, $callback);
        }
    );
    return $loader;
}

sub getName {
    my ($self) = @_;
    return $self->{name};
}

sub getDriver {
    my ($self) = @_;
    return $self->{driver};
}

sub c {
    my ($self, $to) = @_;
    return $self->SUPER::c(
        $to,
        'BusyBird::Output' => sub {
            $self->listenOnGetStatuses(
                sub {
                    my $statuses = shift;
                    my $cloned_statuses = [ map {$_->clone()} @$statuses ];
                    $to->pushStatuses($cloned_statuses);
                }
            );
        },
    );
}

1;
