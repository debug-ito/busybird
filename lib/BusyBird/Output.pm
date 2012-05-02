package BusyBird::Output;
use base ('BusyBird::Object', 'BusyBird::Connector');
use Encode;
use strict;
use warnings;
use DateTime;

use BusyBird::Connector;

my %S = (
    global_header_height => '50px',
    global_side_height => '200px',
    side_width => '150px',
    optional_width => '100px',
    profile_image_section_width => '50px',
);

## my %COMMAND = (
##     NEW_STATUSES => 'new_statuses',
##     CONFIRM => 'confirm',
##     MAINPAGE => 'mainpage',
##     ALL_STATUSES => 'all_statuses',
## );

sub new {
    my ($class, %params) = @_;
    my $self = bless {
        new_statuses => [],
        old_statuses => [],
        status_ids => {},
        mainpage_html => undef,
        pending_req => {
            new_statuses => [],
        }
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
    <link rel="stylesheet" href="/static/style.css" type="text/css" media="screen" />
    <style type="text/css"><!--

div#global_header {
    height: $S{global_header_height};
}

div#global_side {
    top: $S{global_header_height};
    width: $S{side_width};
    height: $S{global_side_height};
}

div#side_container {
    width: $S{side_width};
    margin: $S{global_side_height} 0 0 0;
}

div#main_container {
    margin: $S{global_header_height} $S{optional_width} 0 $S{side_width};
}

div#optional_container {
    width: $S{optional_width};
}

div.status_profile_image {
    width: $S{profile_image_section_width};
}

div.status_main {
    margin: 0 0 0 $S{profile_image_section_width};
}

    --></style>
    <script type="text/javascript" src="/static/jquery.js"></script>
    <script type="text/javascript"><!--
    function bbGetOutputName() {return "$name"}
--></script>
    <script type="text/javascript" src="/static/main.js"></script>
  </head>
  <body>
    <div id="global_header">
    </div>
    <div id="global_side">
    </div>
    <div id="side_container">
    </div>
    <div id="optional_container">
    </div>
    <div id="main_container">
      <ul id="statuses">
      </ul>
      <div id="main_footer">
        <button id="more_button" type="button" onclick="" >More...</button>
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
    ## my @sorted_statuses = sort {$b->getDateTime()->epoch <=> $a->getDateTime()->epoch} @{$self->{new_statuses}};
    my @sorted_statuses = sort {DateTime->compare($b->getDateTime(), $a->getDateTime())} @{$self->{new_statuses}};
    $self->{new_statuses} = \@sorted_statuses;
}

sub _getGlobalIndicesForStatuses {
    my ($self, $condition_func) = @_;
    my @indices = ();
    my $global_index = 0;
    foreach my $status (@{$self->{new_statuses}}, @{$self->{old_statuses}}) {
        local $_ = $status;
        push(@indices, $global_index) if &$condition_func();
        $global_index++;
    }
    return wantarray ? @indices : $indices[0];
}

sub _getSingleStatusesJSONEntries {
    my ($self, $statuses_ref, $is_new, $start_index, $entry_num) = @_;
    my $statuses_num = int(@$statuses_ref);
    $is_new = $is_new ? 1 : 0;
    $start_index = 0 if !defined($start_index);
    if($start_index >= $statuses_num) {
        return [];
    }
    $entry_num = $statuses_num - $start_index if !defined($entry_num);
    if($entry_num <= 0) {
        return [];
    }
    my $end_inc_index = $start_index + $entry_num - 1;
    $end_inc_index = $statuses_num - 1 if $end_inc_index >= $statuses_num;
    my @json_entries = map {$_->getJSON} @$statuses_ref[$start_index .. $end_inc_index];
    return \@json_entries;
}

sub _getStatusesJSONEntries {
    my ($self, $global_start_index, $entry_num) = @_;
    my $new_num = int(@{$self->{new_statuses}});
    my @entries = ();
    return \@entries if $entry_num <= 0;
    $global_start_index = 0 if $global_start_index < 0;
    my $old_entry_num = $entry_num;
    if($global_start_index < $new_num) {
        my $new_entries = $self->_getSingleStatusesJSONEntries($self->{new_statuses}, 1, $global_start_index, $entry_num);
        push(@entries, @$new_entries);
        $old_entry_num = $entry_num - int(@$new_entries);
    }
    if($old_entry_num > 0) {
        my $old_start_index = $global_start_index - $new_num;
        $old_start_index = 0 if $old_start_index < 0;
        my $old_entries = $self->_getSingleStatusesJSONEntries($self->{old_statuses}, 0, $old_start_index, $old_entry_num);
        push(@entries, @$old_entries);
    }
    return \@entries;
}

sub _getNewStatusesJSONEntries {
    my ($self, $start_index, $entry_num) = @_;
    return $self->_getSingleStatusesJSONEntries($self->{new_statuses}, 1, $start_index, $entry_num);
}

sub _getOldStatusesJSONEntries {
    my ($self, $start_index, $entry_num) = @_;
    return $self->_getSingleStatusesJSONEntries($self->{old_statuses}, 0, $start_index, $entry_num);
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
    if(!@$statuses) {
        return;
    }
    unshift(@{$self->{new_statuses}}, @$statuses);
    foreach my $status (@$statuses) {
        $self->{status_ids}{$status->getID()} = 1;
        $status->content->{busybird}{is_new} = 1;
    }
    $self->_sort();
    $self->_limitStatusQueueSize($self->{new_statuses}, $self->{max_new_statuses});

    ## ** TODO: implement Nagle algorithm, i.e., delay the complete event a little to accept more statuses.
    $self->_onCompletePushingStatuses();
}

sub _getPointNameForCommand {
    my ($self, $com_name) = @_;
    return '/' . $self->getName() . '/' . $com_name;
}

sub getRequestPoints {
    my ($self) = @_;
    my @points = ();
    foreach my $method (map {'_requestPoint'. $_} qw(NewStatuses Confirm MainPage AllStatuses)) {
        my ($point_path, $handler) = $self->$method();
        push(@points, [$point_path, $handler]);
    }
    return @points;
}

sub _onCompletePushingStatuses {
    my ($self) = @_;
    ## BusyBird::HTTPD->replyPoint($self->_getPointNameForCommand($COMMAND{NEW_STATUSES}));
    $self->_replyRequestNewStatuses();
}

## sub reply {
##     my ($self, $request_point_name, $detail) = @_;
##     if($request_point_name !~ m|^/([^/]+)/([^/]+)$|) {
##         return ($self->NOT_FOUND);
##     }
##     my ($output_name, $command) = ($1, $2);
##     if($command eq $COMMAND{NEW_STATUSES}) {
##         return $self->_replyNewStatuses($detail);
##     }elsif($command eq $COMMAND{CONFIRM}) {
##         return $self->_replyConfirm($detail);
##     }elsif($command eq $COMMAND{MAINPAGE}) {
##         return $self->_replyMainPage($detail);
##     }elsif($command eq $COMMAND{ALL_STATUSES}) {
##         return $self->_replyAllStatuses($detail);
##     }
##     return ($self->NOT_FOUND);
## }

sub _replyRequestNewStatuses {
    my ($self) = @_;
    if(!@{$self->{new_statuses}} or !@{$self->{pending_req}->{new_statuses}}) {
        return;
    }
    my $json_entries_ref = $self->_getNewStatusesJSONEntries();
    my $ret = "[" . join(",", @$json_entries_ref) . "]";
    while(my $req = pop(@{$self->{pending_req}->{new_statuses}})) {
        $req->env->{'busybird.responder'}->([
            '200',
            ['Content-Type' => "application/json; charset=UTF-8"],
            [$ret],
        ]);
    }
}

sub _requestPointNewStatuses {
    my ($self) = @_;
    my $handler = sub {
        my ($request) = @_;
        return sub {
            $request->env->{'busybird.responder'} = $_[0];
            push(@{$self->{pending_req}->{new_statuses}}, $request);
            $self->_replyRequestNewStatuses();
        };
    };
    return ($self->_getPointNameForCommand('new_statuses'), $handler);
}

## sub _replyNewStatuses {
##     my ($self, $detail) = @_;
##     if(!@{$self->{new_statuses}}) {
##         return ($self->HOLD);
##     }
##     my $json_entries_ref = $self->_getNewStatusesJSONEntries();
##     my $ret = "[" . join(",", @$json_entries_ref) . "]";
##     return ($self->REPLIED, \$ret, "application/json; charset=UTF-8");
## }

## sub _replyConfirm {
##     my ($self, $detail) = @_;
##     unshift(@{$self->{old_statuses}}, @{$self->{new_statuses}});
##     $self->{new_statuses} = [];
##     $self->_limitStatusQueueSize($self->{old_statuses}, $self->{max_old_statuses});
##     my $ret = "Confirm OK";
##     return ($self->REPLIED, \$ret, "text/plain");
## }

sub _requestPointConfirm {
    my ($self) = @_;
    my $handler = sub {
        $_->content->{busybird}{is_new} = 0 foreach @{$self->{new_statuses}};
        unshift(@{$self->{old_statuses}}, @{$self->{new_statuses}});
        $self->{new_statuses} = [];
        $self->_limitStatusQueueSize($self->{old_statuses}, $self->{max_old_statuses});
        return [
            '200',
            ['Content-Type' => 'text/plain'],
            ['Confirm OK'],
        ];
    };
    return ($self->_getPointNameForCommand('confirm'), $handler);
}

sub _requestPointMainPage {
    my ($self) = @_;
    my $handler = sub {
        return [
            '200',
            ['Content-Type' => 'text/html'],
            [$self->{mainpage_html}],
        ];
    };
    return ($self->_getPointNameForCommand('mainpage'), $handler);
}

## sub _replyMainPage {
##     my ($self, $detail) = @_;
##     my $html = $self->{mainpage_html};
##     return ($self->REPLIED, \$html, 'text/html');
## }

sub _requestPointAllStatuses {
    my ($self) = @_;
    my $handler = sub {
        my ($request) = @_;
        my $detail = $request->parameters;
        my $new_num = int(@{$self->{new_statuses}});
        my $page = ($detail->{page} or 1) - 1;
        $page = 0 if $page < 0;
        my $per_page = $detail->{per_page};
        my $json_entries;
        my $start_global_index = 0;

        if($detail->{max_id}) {
            $start_global_index = $self->_getGlobalIndicesForStatuses(sub { $_->getID eq $detail->{max_id} });
            $start_global_index = 0 if !defined($start_global_index);
        }
        if($per_page) {
            $json_entries = $self->_getStatusesJSONEntries($start_global_index + $page * $per_page, $per_page);
        }else {
            $per_page = 20;
            if($start_global_index < $new_num) {
                if($page == 0) {
                    $json_entries = $self->_getStatusesJSONEntries($start_global_index, $per_page + $new_num - $start_global_index);
                }else {
                    $json_entries = $self->_getStatusesJSONEntries($new_num + $page * $per_page, $per_page);
                }
            }else {
                $json_entries = $self->_getStatusesJSONEntries($start_global_index + $page * $per_page, $per_page);
            }
        }
        my $ret = '['. join(',', @$json_entries) .']';
        ## return ($self->REPLIED, \$ret, );
        return [
            '200',
            ['Content-Type' => 'application/json; charset=UTF-8'],
            [$ret],
        ];
    };
    return ($self->_getPointNameForCommand('all_statuses'), $handler);
}

## sub _replyAllStatuses {
##     my ($self, $detail) = @_;
##     my $new_num = int(@{$self->{new_statuses}});
##     my $page = ($detail->{page} or 1) - 1;
##     $page = 0 if $page < 0;
##     my $per_page = $detail->{per_page};
##     my $json_entries;
##     my $start_global_index = 0;
## 
##     if($detail->{max_id}) {
##         $start_global_index = $self->_getGlobalIndicesForStatuses(sub { $_->getID eq $detail->{max_id} });
##         $start_global_index = 0 if !defined($start_global_index);
##     }
##     if($per_page) {
##         $json_entries = $self->_getStatusesJSONEntries($start_global_index + $page * $per_page, $per_page);
##     }else {
##         $per_page = 20;
##         if($start_global_index < $new_num) {
##             if($page == 0) {
##                 $json_entries = $self->_getStatusesJSONEntries($start_global_index, $per_page + $new_num - $start_global_index);
##             }else {
##                 $json_entries = $self->_getStatusesJSONEntries($new_num + $page * $per_page, $per_page);
##             }
##         }else {
##             $json_entries = $self->_getStatusesJSONEntries($start_global_index + $page * $per_page, $per_page);
##         }
##     }
##     my $ret = '['. join(',', @$json_entries) .']';
##     return ($self->REPLIED, \$ret, 'application/json; charset=UTF-8');
## }

sub c {
    my ($self, $to) = @_;
    return $self->SUPER::c(
        $to,
        'BusyBird::HTTPD' => sub {
            $to->addRequestPoints($self->getRequestPoints());
        },
    );
}

1;
