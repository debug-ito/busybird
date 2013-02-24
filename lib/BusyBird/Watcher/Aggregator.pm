package BusyBird::Watcher::Aggregator;
use strict;
use warnings;
use Async::Selector 1.03;
use base qw(BusyBird::Watcher Async::Selector::Aggregator);

sub new {
    my ($class, @args) = @_;
    return $class->SUPER::new(@args);
}

1;
