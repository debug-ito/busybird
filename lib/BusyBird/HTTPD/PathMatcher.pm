package BusyBird::HTTPD::PathMatcher;
use strict;
use warnings;
use Carp;

sub new {
    my ($class, $match_obj) = @_;
    my $type = ref($match_obj);
    if(!$type) {
        return BusyBird::HTTPD::PathMatcher::String->new($match_obj);
    }elsif($type eq 'HASH') {
        return BusyBird::HTTPD::PathMatcher::Hash->new($match_obj);
    }elsif($type eq 'ARRAY') {
        my %hash = ( map { $_ => $match_obj->[$_] } 0..$#{$match_obj} );
        return BusyBird::HTTPD::PathMatcher::Hash->new(\%hash);
    }elsif($type eq 'Regexp') {
        return BusyBird::HTTPD::PathMatcher::Regexp->new($match_obj);
    }else {
        return BusyBird::HTTPD::PathMatcher::Object->new($match_obj);
    }
}

sub match {
    my ($self, $path) = @_;
    croak 'Must be implemented in subclasses';
    return 0;
}

sub toString {
    my ($self) = @_;
    croak 'Must be implemented in subclasses';
    return '';
}

package BusyBird::HTTPD::PathMatcher::String;
use base ('BusyBird::HTTPD::PathMatcher');
use strict;
use warnings;

sub new {
    my ($class, $match_string) = @_;
    return bless \$match_string, $class;
}

sub match {
    my ($self, $path) = @_;
    return () if !defined($path);
    if($$self eq $path) {
        return wantarray ? ($path) : $path;
    }else {
        return ();
    }
}

sub toString {
    return ${$_[0]};
}

package BusyBird::HTTPD::PathMatcher::Hash;
use base ('BusyBird::HTTPD::PathMatcher');
use strict;
use warnings;

sub new {
    my ($class, $match_hash) = @_;
    return bless $match_hash, $class;
}

sub match {
    my ($self, $path) = @_;
    return () if !defined($path);
    foreach my $key (keys %$self) {
        my $val = $self->{$key};
        if($val eq $path) {
            my @ret = ($path, $key);
            return wantarray ? @ret : $ret[0];
        }
    }
    return ();
}

sub toString {
    my ($self) = @_;
    return join(',', values %$self);
}

package BusyBird::HTTPD::PathMatcher::Regexp;
use base ('BusyBird::HTTPD::PathMatcher');
use strict;
use warnings;

sub new {
    my ($class, $match_re) = @_;
    return bless {re => $match_re}, $class;
}

sub match {
    my ($self, $path) = @_;
    my @matched = ($path =~ $self->{re});
    if(!@matched) {
        return ();
    }
    my @ret = ($path, @matched);
    return wantarray ? @ret : $ret[0];
}

sub toString {
    my ($self) = @_;
    return sprintf("%s", $self->{re});
}


package BusyBird::HTTPD::PathMatcher::Object;
use base ('BusyBird::HTTPD::PathMatcher');
use strict;
use warnings;

sub new {
    my ($class, $match_obj) = @_;
    return bless {obj => $match_obj}, $class;
}

sub match {
    my ($self, $path) = @_;
    return $self->{obj}->match($path);
}

sub toString {
    my ($self) = @_;
    return $self->{obj}->toString();
}

1;


