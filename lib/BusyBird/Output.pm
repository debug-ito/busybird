package BusyBird::Output;
use base ('BusyBird::Object', 'BusyBird::RequestListener');
use Encode;
use strict;
use warnings;
use DateTime;

my %COMMAND = (
    NEW_STATUSES => 'new_statuses',
    CONFIRM => 'confirm',
    MAINPAGE => 'mainpage',
    ALL_STATUSES => 'all_statuses',
);

sub new {
    my ($class, %params) = @_;
    my $self = bless {
        new_statuses => [],
        old_statuses => [],
        status_ids => {},
        mainpage_html => undef,
    }, $class;
    $self->_setParam(\%params, 'name', undef, 1);
    $self->_setParam(\%params, 'max_old_statuses', 1024);
    $self->_setParam(\%params, 'max_new_statuses', 2048);
    $self->_initMainPage();
    return $self;
}

sub _initMainPage {
    my ($self) = @_;
    my $name = $self->getName();
    $self->{mainpage_html} = <<"END";
<html>
  <head>
    <title>$name - BusyBird</title>
    <meta content='text/html; charset=UTF-8' http-equiv='Content-Type'/>
    <link rel="stylesheet" href="/style.css" type="text/css" media="screen" />
    <script type="text/javascript" src="/jquery.js"></script>
    <script type="text/javascript"><!--
    function bbGetOutputName() {return "$name"}
--></script>
    <script type="text/javascript" src="/main.js"></script>
  </head>
  <body>
    <div id="global_header">
    </div>
    <div id="global_main">
      <div id="side_container">
        <div id="global_side">
        </div>
        <div id="local_side">
        </div>
      </div>
      <ul id="statuses">
      </ul>
      <div id="optional_container">
      </div>
    </div>
  </body>
</html>
END
}

sub getName {
    my $self = shift;
    return $self->{name};
}

sub _uniqStatuses {
    my ($self, $statuses) = @_;
    ## my %ids = ();
    ## foreach my $status (@{$self->{statuses}}) {
    ##     ## print STDERR Dumper($status);
    ##     $ids{$status->{bb_id}} = 1;
    ## }
    my $uniq_statuses = [];
    foreach my $status (@$statuses) {
        if(!defined($self->{status_ids}{$status->getID()})) {
            push(@$uniq_statuses, $status);
        }
    }
    return $uniq_statuses;
}

sub _sort {
    my ($self) = @_;
    my @sorted_statuses = sort {$b->getDateTime()->epoch <=> $a->getDateTime()->epoch} @{$self->{new_statuses}};
    $self->{new_statuses} = \@sorted_statuses;
}

sub _getNewStatusesJSONEntries {
    my ($self) = @_;
    my @json_entries = map {$_->getJSON(is_new => 1)} @{$self->{new_statuses}};
    return \@json_entries;
}

sub _getOldStatusesJSONEntries {
    my ($self, $start_index, $entry_num) = @_;
    if($entry_num <= 0) {
        return [];
    }
    if($start_index >= int(@{$self->{old_statuses}})) {
        return [];
    }
    my $end_inc_index = $start_index + $entry_num - 1;
    $end_inc_index = int(@{$self->{old_statuses}}) - 1 if $end_inc_index >= int(@{$self->{old_statuses}});
    my @json_entries = map {$_->getJSON(is_new => 0)} @{$self->{old_statuses}}[$start_index .. $end_inc_index];
    return \@json_entries;
}

sub _limitStatusQueueSize {
    my ($self, $status_queue, $limit_size) = @_;
    while(int(@$status_queue) > $limit_size) {
        my $discarded_status = pop(@$status_queue);
        delete $self->{status_ids}->{$discarded_status->getID};
    }
}

sub pushStatuses {
    my ($self, $statuses) = @_;
    $statuses = $self->_uniqStatuses($statuses);
    unshift(@{$self->{new_statuses}}, @$statuses);
    foreach my $status (@$statuses) {
        $self->{status_ids}{$status->getID()} = 1;
    }
    $self->_sort();
    $self->_limitStatusQueueSize($self->{new_statuses}, $self->{max_new_statuses});
    
    ## ** we should do classification here, or its better to do it in another method??
}

sub _getPointNameForCommand {
    my ($self, $com_name) = @_;
    return '/' . $self->getName() . '/' . $com_name;
}

sub getRequestPoints {
    my ($self) = @_;
    return map { $self->_getPointNameForCommand($_) } (values %COMMAND);
}

sub onCompletePushingStatuses {
    my ($self) = @_;
    BusyBird::HTTPD->replyPoint($self->_getPointNameForCommand($COMMAND{NEW_STATUSES}));
}

sub reply {
    my ($self, $request_point_name, $detail) = @_;
    if($request_point_name !~ m|^/([^/]+)/([^/]+)$|) {
        return ($self->NOT_FOUND);
    }
    my ($output_name, $command) = ($1, $2);
    if($command eq $COMMAND{NEW_STATUSES}) {
        return $self->_replyNewStatuses($detail);
    }elsif($command eq $COMMAND{CONFIRM}) {
        return $self->_replyConfirm($detail);
    }elsif($command eq $COMMAND{MAINPAGE}) {
        return $self->_replyMainPage($detail);
    }elsif($command eq $COMMAND{ALL_STATUSES}) {
        return $self->_replyAllStatuses($detail);
    }
    return ($self->NOT_FOUND);
}

sub _replyNewStatuses {
    my ($self, $detail) = @_;
    if(!@{$self->{new_statuses}}) {
        return ($self->HOLD);
    }
    my $json_entries_ref = $self->_getNewStatusesJSONEntries();
    my $ret = "[" . join(",", @$json_entries_ref) . "]";
    return ($self->REPLIED, \$ret, "application/json; charset=UTF-8");
}

sub _replyConfirm {
    my ($self, $detail) = @_;
    unshift(@{$self->{old_statuses}}, @{$self->{new_statuses}});
    $self->{new_statuses} = [];
    $self->_limitStatusQueueSize($self->{old_statuses}, $self->{max_old_statuses});
    my $ret = "Confirm OK";
    return ($self->REPLIED, \$ret, "text/plain");
}

sub _replyMainPage {
    my ($self, $detail) = @_;
    my $html = $self->{mainpage_html};
    return ($self->REPLIED, \$html, 'text/html');
}

sub _replyAllStatuses {
    my ($self, $detail) = @_;
    my $page = ($detail->{page} or 1) - 1;
    $page = 0 if $page < 0;
    my $per_page = ($detail->{per_page} or 20);
    my $new_jsons_ref = [];
    if($page == 0) {
        $new_jsons_ref = $self->_getNewStatusesJSONEntries();
    }
    my $old_jsons_ref = $self->_getOldStatusesJSONEntries($page * $per_page, $per_page);
    my $ret = '['. join(',', @$new_jsons_ref, @$old_jsons_ref) .']';
    return ($self->REPLIED, \$ret, 'application/json; charset=UTF-8');
}

1;
