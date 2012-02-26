package BusyBird::StaticContent;
use base ('BusyBird::RequestListener');
use strict;
use warnings;

use File::MimeInfo;
use IO::File;
use BusyBird::Log ('bblog');

my %MIME_MAP = (
    html => 'text/html',
    txt => 'text/plain',
    js => 'text/javascript',
    css => 'text/css',
    );

my @CONTENTS = qw(style.css index.html jquery.js shaper.js favicon.ico sample.png);

sub new {
    my ($class, $content_dir) = @_;
    $content_dir =~ s|/+$||g;
    my $self = bless {'content_dir' => $content_dir}, $class;
    my %contents = map { ('/' . $_) => 1 } @CONTENTS;
    $self->{contents} = \%contents;
    return $self;
}

sub getRequestPoints {
    my ($self) = @_;
    return keys %{$self->{contents}};
}

sub reply {
    my ($self, $request_point_name, $detail) = @_;
    if(!defined($self->{contents}{$request_point_name})) {
        return ($self->NOT_FOUND);
    }
    $request_point_name =~ s|^/+||;
    my $path = $self->{content_dir}."/".$request_point_name;
    my $mimetype = $self->_getMimeForFilePath($path);
    &bblog("MIME: $mimetype");
    my $file = IO::File->new();
    if(!$file->open($path, "r")) {
        return ($self->NOT_FOUND);
    }
    my $filedata = '';
    {
        local $/ = undef;
        $filedata = $file->getline();
    }
    $file->close();
    return ($self->REPLIED, \$filedata, $mimetype);
}

sub _getMimeForFilePath {
    my ($class_self, $path) = @_;
    if($path =~ m|\.([^\.]+)$|) {
        my $ext = $1;
        $ext = lc($ext);
        if(defined($MIME_MAP{$ext})) {
            return $MIME_MAP{$ext};
        }
    }
    my $mimetype = mimetype($path);
    $mimetype = 'application/octet-stream' if !defined($mimetype);
    return $mimetype;
}

1;
