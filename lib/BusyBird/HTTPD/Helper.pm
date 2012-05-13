package BusyBird::HTTPD::Helper;
use strict;
use warnings;
use base ('Exporter');

our @EXPORT_OK = qw(httpResSimple);

sub httpResSimple {
    my ($status, $message, $mime) = @_;
    $mime ||= 'text/plain';
    return [
        "$status",
        ['Content-Type' => $mime],
        [ref($message) ? $$message : $message],
    ];
}

1;
