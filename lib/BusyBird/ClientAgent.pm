package BusyBird::ClientAgent;
use DateTime;

sub new() {
    my ($class) = @_;
    my $self = {
        document => {
            output => {},
        },
    };
    return bless $self, $class;
}

sub addOutput() {
    my ($self, $stream_name, $statuses) = @_;
    if(!defined($self->{document}{output}{$stream_name})) {
        $self->{document}{output}{$stream_name} = $statuses;
    }else {
        unshift(@{$self->{document}{output}{$stream_name}}, @$statuses);
    }

    ## foreach my $status (@{$self->{document}{output}{$stream_name}}) {
    ##     print Encode::encode('utf8', sprintf ("INFO: Pushed to client agent from output %s: ID:%s SRC:%s/%s TEXT:%s at:%s_%s\n",
    ##                                           $stream_name, $status->{bb_id}, $status->{bb_source_name}, $status->{bb_input_name},
    ##                                           $status->{bb_text}, $status->{bb_datetime}->ymd(), $status->{bb_datetime}->hms()
    ##                          ));
    ## }
}

sub getHTMLHead() {
    my ($self, $stream_name) = @_;
    return <<END;
<html>
<head>
<title>$stream_name - BusyBird</title>
<meta content='text/html; charset=UTF-8' http-equiv='Content-Type'/>
</head>
<style type="text/css"><!--
.status_container {
  margin: 5px 30px;
  width: 700px;
}
.status_time {
    text-align: right;
  text-weight: bold;
  color: red;
  float: right;
}
div {
  border: solid 1px red;
}
--></style>
<body>
END
}

sub getHTMLFoot() {
    return <<END;
</body>
</html>
END
}

sub getHTMLStream() {
    my ($self, $stream_name) = @_;
    return '' if !defined($self->{document}{output}{$stream_name});
    my $ret = '';
    my $format = <<END;
<div id="%s" class="status_container">
  <div class="status_head">
    <div class="status_time">%s&nbsp;%s</div>
    <div class="status_source"><img src="%s" alt="icon" />&nbsp;%s</div>
  </div>
  <div class="status_body">%s</div>
  <div class="status_foot"><span class="status_score">%.2f</span>%s</div>
</div>
END
    foreach my $status (@{$self->{document}{output}{$stream_name}}) {
        $ret .= sprintf($format,
                        $status->{bb_id},
                        $status->{bb_datetime}->ymd, $status->{bb_datetime}->hms,
                        $status->{bb_icon_url},
                        $status->{bb_source_name},
                        $status->{bb_text},
                        $status->{bb_score},
                        ($status->{bb_reply_to_name} ? ('in reply to ' . $status->{bb_reply_to_name}) : ""),
            );
    }
    return $ret;
}


1;

