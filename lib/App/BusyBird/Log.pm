package App::BusyBird::Log;
use strict;
use warnings;

use Exporter qw(import);

use strict;
use warnings;

our @EXPORT_OK = qw(bblog);

my $instance = __PACKAGE__->new();

sub bblog {
    my ($level, $msg) = @_;
    $instance->log($level, $msg);
}

sub new {
    my ($class) = @_;
    my $self = bless {}, $class;
    return $self;
}

sub log {
    my ($self, $level, $msg) = @_;
    print STDERR ("$level: $msg\n");
}

sub logger {
    my ($class) = @_;
    return $instance;
}

1;

