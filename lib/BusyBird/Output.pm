package BusyBird::Output;
use base ('BusyBird::Connector');
use Encode;
use strict;
use warnings;
use DateTime;
use IO::File;
use Carp;

use BusyBird::Filter;
use BusyBird::HTTPD::Helper qw(httpResSimple);
use BusyBird::Status;
use BusyBird::Status::Buffer;
use BusyBird::ComponentManager;
use BusyBird::Log qw(bblog);
use BusyBird::Util ('setParam');

my %S = (
    global_header_height => '50px',
    global_side_height => '200px',
    side_width => '150px',
    optional_width => '100px',
    profile_image_section_width => '50px',
);

sub new {
    my ($class, %params) = @_;
    push(local @BusyBird::Util::CARP_NOT, __PACKAGE__);
    $params{max_old_statuses} ||= 1024;
    $params{max_new_statuses} ||= 2048;
    my $self = bless {
        new_status_buffer => BusyBird::Status::Buffer->new(max_size => $params{max_new_statuses}),
        old_status_buffer => BusyBird::Status::Buffer->new(max_size => $params{max_old_statuses}),
        mainpage_html => undef,
        pending_req => {
            new_statuses => [],
        },
        filters => {
            map { $_ => BusyBird::Filter->new() } qw(parent_input input new_status)
        },
    }, $class;
    $self->setParam(\%params, 'name', undef, 1);
    $self->setParam(\%params, 'no_persistent', 0);
    $self->setParam(\%params, 'sync_with_input', 0);
    $self->setParam(\%params, 'auto_confirm', 0);
    $self->_initMainPage();
    $self->_initFilters();
    BusyBird::ComponentManager->register('output', $self);
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

sub _getStatusesFilePath {
    my ($self) = @_;
    return "bboutput_" . $self->getName() . "_statuses.json";
}

sub saveStatuses {
    my ($self, $force) = @_;
    return if $self->{no_persistent} && !$force;
    my $serialized_statuses = BusyBird::Status->serialize(
        [@{$self->{new_status_buffer}->get}, @{$self->{old_status_buffer}->get}]
    );
    my $filepath = $self->_getStatusesFilePath();
    my $file = IO::File->new();
    if(!$file->open($filepath, "w")) {
        croak "Cannot open $filepath to write to.";
    }
    $file->print($serialized_statuses);
    $file->close();
    &bblog("Output " . $self->getName . ": Statuses are saved to $filepath.");
}

sub loadStatuses {
    my ($self, $force) = @_;
    return if $self->{no_persistent} && !$force;
    my $filepath = $self->_getStatusesFilePath();
    my $file = IO::File->new();
    if(!$file->open($filepath, "r")) {
        croak "Cannot open $filepath to read.";
    }
    my $data;
    {
        local $/ = undef;
        $data = $file->getline();
    }
    $file->close();
    my $deserialized = BusyBird::Status->deserialize($data);
    my @new_temp = ();
    my @old_temp = ();
    foreach my $des_status (@$deserialized) {
        my $is_new = $des_status->{busybird}{is_new};
        croak "Loaded status does not have busybird/is_new flag." if !defined($is_new);
        if($is_new) {
            push(@new_temp, $des_status);
        }else {
            push(@old_temp, $des_status);
        }
        ## my ($queue, $dict) = ($is_new)
        ##     ? ($self->{new_statuses}, $self->{new_ids})
        ##         : ($self->{old_statuses}, $self->{old_ids});
        ## push(@$queue, $des_status);
        ## $dict->{$des_status->{id}} = 1;
    }
    $self->{new_status_buffer}->clear->unshift(@new_temp);
    $self->{old_status_buffer}->clear->unshift(@old_temp);
    &bblog("Output " . $self->getName() . ": statuses are loaded from $filepath.");
}

sub _syncFilter {
    my ($self) = @_;
    return sub {
        my ($statuses, $cb) = @_;
        my %input_ids = map { $_->{id} => 1 } @$statuses;
        foreach my $buffer ($self->{new_status_buffer}, $self->{old_status_buffer}) {
            my @new_queue = ();
            foreach my $status (@{$buffer->get}) {
                if(defined($input_ids{$status->{id}})) {
                    push(@new_queue, $status);
                }
            }
            $buffer->clear->unshift(@new_queue);
        }
        ## foreach my $queue_name ('new', 'old') {
        ##     my ($queue, $id_dict) = @{$self}{"${queue_name}_statuses", "${queue_name}_ids"};
        ##     my @new_queue = ();
        ##     my %new_dict = ();
        ##     foreach my $status (@$queue) {
        ##         if(defined($input_ids{$status->{id}})) {
        ##             push(@new_queue, $status);
        ##             $new_dict{$status->{id}} = 1;
        ##         }
        ##     }
        ##     @$queue = @new_queue;
        ##     %$id_dict = %new_dict;
        ## }
        $cb->($statuses);
    };
}

sub _initFilters {
    my ($self) = @_;
    $self->{filters}->{parent_input}->push(
        $self->{filters}->{input},
        $self->{sync_with_input} ? $self->_syncFilter : undef,
        sub {
            my ($statuses, $cb) = @_;
            $cb->($self->_uniqStatuses($statuses));
        },
        $self->{filters}->{new_status}
    );
}

sub getInputFilter {
    my $self = shift;
    return $self->{filters}->{input};
}

sub getNewStatusFilter {
    my $self = shift;
    return $self->{filters}->{new_status};
}

sub getName {
    my $self = shift;
    return $self->{name};
}

sub _isUniqueID {
    my ($self, $id) = @_;
    return (!$self->{new_status_buffer}->contains($id) && !$self->{old_status_buffer}->contains($id));
    ## return (!defined($self->{old_ids}{$id})
    ##             && !defined($self->{new_ids}{$id}));
}

sub _uniqStatuses {
    my ($self, $statuses) = @_;
    my $uniq_statuses = [];
    foreach my $status (@$statuses) {
        if($self->_isUniqueID($status->{id})) {
            push(@$uniq_statuses, $status);
        }
    }
    return $uniq_statuses;
}

sub _sort {
    my ($self) = @_;
    $self->{new_status_buffer}->sort();
    ## my @sorted_statuses = sort {$b->getDateTime()->epoch <=> $a->getDateTime()->epoch} @{$self->{new_statuses}};
    ## my @sorted_statuses = sort {DateTime->compare($b->{created_at}, $a->{created_at})} @{$self->{new_statuses}};
    ## $self->{new_statuses} = \@sorted_statuses;
}

sub _getGlobalIndicesForStatuses {
    my ($self, $condition_func) = @_;
    my @indices = ();
    my $global_index = 0;
    foreach my $status (@{$self->{new_status_buffer}->get}, @{$self->{old_status_buffer}->get}) {
        local $_ = $status;
        push(@indices, $global_index) if &$condition_func();
        $global_index++;
    }
    return wantarray ? @indices : $indices[0];
}

## sub _getSingleStatuses {
##     my ($self, $statuses_ref, $start_index, $entry_num) = @_;
##     my $statuses_num = int(@$statuses_ref);
##     $start_index = 0 if !defined($start_index);
##     if($start_index >= $statuses_num) {
##         return [];
##     }
##     $entry_num = $statuses_num - $start_index if !defined($entry_num);
##     if($entry_num <= 0) {
##         return [];
##     }
##     my $end_inc_index = $start_index + $entry_num - 1;
##     $end_inc_index = $statuses_num - 1 if $end_inc_index >= $statuses_num;
##     return [ @$statuses_ref[$start_index .. $end_inc_index] ];
## }

sub _getStatuses {
    my ($self, $global_start_index, $entry_num) = @_;
    my $new_num = $self->{new_status_buffer}->size;
    my @entries = ();
    return \@entries if $entry_num <= 0;
    $global_start_index = 0 if $global_start_index < 0;
    my $old_entry_num = $entry_num;
    if($global_start_index < $new_num) {
        my $new_entries = $self->{new_status_buffer}->get($global_start_index, $entry_num);
        push(@entries, @$new_entries);
        $old_entry_num = $entry_num - int(@$new_entries);
    }
    if($old_entry_num > 0) {
        my $old_start_index = $global_start_index - $new_num;
        $old_start_index = 0 if $old_start_index < 0;
        my $old_entries = $self->{old_status_buffer}->get($old_start_index, $old_entry_num);
        push(@entries, @$old_entries);
    }
    return \@entries;
}

sub getNewStatuses {
    my ($self, $start_index, $entry_num) = @_;
    ## return $self->_getSingleStatuses($self->{new_statuses}, $start_index, $entry_num);
    return $self->{new_status_buffer}->get($start_index, $entry_num);
}

sub getOldStatuses {
    my ($self, $start_index, $entry_num) = @_;
    ## return $self->_getSingleStatuses($self->{old_statuses}, $start_index, $entry_num);
    return $self->{old_status_buffer}->get($start_index, $entry_num);
}

## sub _limitStatusQueueSize {
##     my ($self, $queue_name) = @_;
##     my ($status_queue, $limit_size, $id_dict) = @{$self}{"${queue_name}_statuses", "max_${queue_name}_statuses", "${queue_name}_ids"};
##     while(int(@$status_queue) > $limit_size) {
##         my $discarded_status = pop(@$status_queue);
##         delete $id_dict->{$discarded_status->{id}};
##     }
## }

sub pushStatuses {
    my ($self, $statuses, $cb) = @_;
    $self->{filters}->{parent_input}->execute(
        $statuses, sub {
            my ($filtered_statuses) = @_;
            if(!@$filtered_statuses) {
                $cb->($filtered_statuses) if defined($cb);
                return;
            }
            ## unshift(@{$self->{new_statuses}}, @$filtered_statuses);
            foreach my $status (@$filtered_statuses) {
                ## $self->{new_ids}{$status->{id}} = 1;
                $status->{busybird}{is_new} = 1;
            }
            $self->{new_status_buffer}->unshift(@$filtered_statuses)->sort->truncate;
            
            ## $self->_sort();
            ## ## $self->_limitStatusQueueSize($self->{new_statuses}, $self->{max_new_statuses});
            ## $self->_limitStatusQueueSize('new');

            ## ** TODO: implement Nagle algorithm, i.e., delay the complete event a little to accept more statuses.
            $self->_replyRequestNewStatuses();
            $self->confirm if $self->{auto_confirm};
            $cb->($filtered_statuses) if defined($cb);
        }
    );
    #### $statuses = $self->_uniqStatuses($statuses);
    #### if(!@$statuses) {
    ####     return;
    #### }
    #### unshift(@{$self->{new_statuses}}, @$statuses);
    #### foreach my $status (@$statuses) {
    ####     $self->{status_ids}{$status->content->{id}} = 1;
    ####     $status->content->{busybird}{is_new} = 1;
    #### }
    #### $self->_sort();
    #### $self->_limitStatusQueueSize($self->{new_statuses}, $self->{max_new_statuses});
    #### 
    #### ## ** TODO: implement Nagle algorithm, i.e., delay the complete event a little to accept more statuses.
    #### $self->_replyRequestNewStatuses();
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

sub _replyRequestNewStatuses {
    my ($self) = @_;
    if($self->{new_status_buffer}->size <= 0 or !@{$self->{pending_req}->{new_statuses}}) {
        return;
    }
    ## my $new_statuses = $self->getNewStatuses();
    ## my $ret = "[" . join(",", map {$_->format_json()} @$new_statuses) . "]";
    while(my $req = pop(@{$self->{pending_req}->{new_statuses}})) {
        my $ret = BusyBird::Status->format($req->env->{'busybird.format'}, $self->{new_status_buffer}->get);
        if(defined($ret)) {
            $req->env->{'busybird.responder'}->(httpResSimple(
                200, \$ret, BusyBird::Status->mime($req->env->{'busybird.format'})
            ));
        }else {
            $req->env->{'busybird.responder'}->(httpResSimple(
                400, 'Unsupported format.'
            ));
        }
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
##     my $json_entries_ref = $self->getNewStatusesJSONEntries();
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

sub confirm {
    my ($self) = @_;
    my $new_statuses = $self->{new_status_buffer}->get;
    $_->{busybird}{is_new} = 0 foreach @$new_statuses;
    $self->{old_status_buffer}->unshift(@$new_statuses)->truncate;
    ## unshift(@{$self->{old_statuses}}, @{$self->{new_statuses}});
    ## foreach my $id (keys %{$self->{new_ids}}) {
    ##     $self->{old_ids}{$id} = 1;
    ## }
    $self->{new_status_buffer}->clear;
    ## $self->{new_statuses} = [];
    ## $self->{new_ids} = {};
    ## $self->_limitStatusQueueSize($self->{old_statuses}, $self->{max_old_statuses});
    ## $self->_limitStatusQueueSize('old');
}

sub _requestPointConfirm {
    my ($self) = @_;
    my $handler = sub {
        $self->confirm();
        return httpResSimple(200, "Confirm OK");
    };
    return ($self->_getPointNameForCommand('confirm'), $handler);
}

sub _requestPointMainPage {
    my ($self) = @_;
    my $handler = sub {
        return httpResSimple(200, \$self->{mainpage_html}, 'text/html');
    };
    return ($self->_getPointNameForCommand('index'), $handler);
}

## sub _replyMainPage {
##     my ($self, $detail) = @_;
##     my $html = $self->{mainpage_html};
##     return ($self->REPLIED, \$html, 'text/html');
## }

sub getPagedStatuses {
    my ($self, %params) = @_;
    my $DEFAULT_PER_PAGE = 20;
    ## my $new_num = int(@{$self->{new_statuses}});
    my $new_num = $self->{new_status_buffer}->size;
    my $page = $params{page};
    if($page && $page =~ /^[0-9]+$/) {
        $page = $page - 1;
    }else {
        $page = 0;
    }
    $page = 0 if $page < 0;
    
    my $per_page = $params{per_page};
    my $start_global_index = 0;
    my $end_global_index;

    if($params{max_id}) {
        $start_global_index = $self->_getGlobalIndicesForStatuses(sub { $_->{id} eq $params{max_id} });
        $start_global_index = 0 if !defined($start_global_index);
    }
    if($params{since_id}) {
        $end_global_index = $self->_getGlobalIndicesForStatuses(sub { $_->{id} eq $params{since_id} });
    }

    my ($get_start, $get_num);
    if($per_page && $per_page =~ /^[0-9]+$/) {
        ($get_start, $get_num) = ($start_global_index + $page * $per_page, $per_page);
    }else {
        $per_page = $DEFAULT_PER_PAGE;
        if($start_global_index < $new_num) {
            if($page == 0) {
                ($get_start, $get_num) = ($start_global_index, $per_page + $new_num - $start_global_index);
            }else {
                ($get_start, $get_num) = ($new_num + $page * $per_page, $per_page);
            }
        }else {
            ($get_start, $get_num) = ($start_global_index + $page * $per_page, $per_page);
        }
    }

    if(defined($end_global_index)) {
        my $num_to_end = $end_global_index - $get_start;
        $get_num = $num_to_end if $num_to_end < $get_num;
    }

    return $self->_getStatuses($get_start, $get_num);
}

sub _requestPointAllStatuses {
    my ($self) = @_;
    my $handler = sub {
        my ($request) = @_;
        my $detail = $request->parameters;
        my $statuses = $self->getPagedStatuses(%$detail);
        my $ret = BusyBird::Status->format($request->env->{'busybird.format'}, $statuses);
        if(!defined($ret)) {
            return httpResSimple(400, 'Unsupported format');
        }
        return httpResSimple(200, \$ret, BusyBird::Status->mime($request->env->{'busybird.format'}));
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
