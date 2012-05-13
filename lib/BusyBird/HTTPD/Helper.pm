package BusyBird::HTTPD::Helper;
use strict;
use warnings;
use base ('Exporter');

our @EXPORT_OK = qw(httpResSimple);

sub httpResSimple {
    my ($status, $message_ref, $mime) = @_;
    $mime ||= 'text/plain';
    return [
        "$status",
        ['Content-Type' => $mime],
        [$$message_ref],
    ];
}

1;
