package BusyBird::Output;
use base ('BusyBird::RequestListener');
use Encode;
use strict;
use warnings;
use DateTime;

my %COMMAND = (
    NEW_STATUSES => 'new_statuses',
    CONFIRM => 'confirm',
    MAINPAGE => 'mainpage',
);

sub new {
    my ($class, $name) = @_;
    my $self = {
        name => $name,
        new_statuses => [],
        old_statuses => [],
        status_ids => {},
    };
    return bless $self, $class;
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

sub pushStatuses {
    my ($self, $statuses) = @_;
    $statuses = $self->_uniqStatuses($statuses);
    unshift(@{$self->{new_statuses}}, @$statuses);
    foreach my $status (@$statuses) {
        $self->{status_ids}{$status->getID()} = 1;
    }
    $self->_sort();
    
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
    }
    return ($self->NOT_FOUND);
}

sub _replyNewStatuses {
    my ($self, $detail) = @_;
    if(!@{$self->{new_statuses}}) {
        return ($self->HOLD);
    }
    my @json_entries = map { $_->getJSON() } @{$self->{new_statuses}};
    my $ret = "[" . join(",", @json_entries) . "]";
    return ($self->REPLIED, \$ret, "application/json; charset=UTF-8");
}

sub _replyConfirm {
    my ($self, $detail) = @_;
    unshift(@{$self->{old_statuses}}, @{$self->{new_statuses}});
    $self->{new_statuses} = [];
    my $ret = "Confirm OK";
    return ($self->REPLIED, \$ret, "text/plain");
}

sub _replyMainPage {
    my ($self, $detail) = @_;
    my $name = $self->getName();
    my $html = <<"END";
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
    <ul id="statuses">
    </ul>
  </body>
</html>
END
    return ($self->REPLIED, \$html, 'text/html');
}

1;
