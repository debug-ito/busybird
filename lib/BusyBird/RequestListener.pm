package BusyBird::RequestListener;
use strict;
use warnings;

sub REPLIED   { 0 }
sub HOLD      { 1 }
sub NOT_FOUND { 2 }

sub reply {
    my ($self, $notify_point_name, $detail) = @_;
    my ($result_code, $content, $mime) = (NOT_FOUND, '', '');
    die "Must be implemented in subclasses";
    return ($result_code, \$content, $mime);
}

sub getRequestPoints {
    my $self = shift;
    die "Must be implemented in subclasses";
    return ();
}


1;

