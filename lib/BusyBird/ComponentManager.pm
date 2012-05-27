package BusyBird::ComponentManager;

use strict;
use warnings;

use AnyEvent;
use BusyBird::Output;
use BusyBird::Input;
use BusyBird::Log qw(bblog);

my $g_self = undef;

sub _new {
    my ($class) = @_;
    my $self = bless {
        input => [],
        output => [],
        signal_watchers => {},
    }, $class;
    foreach my $signame (qw(TERM INT HUP QUIT)) {
        $self->_registerSignalHandler($signame, sub { $self->_handlerQuit })
    }
    return $self;
}

sub init {
    my ($class) = @_;
    $g_self = $class->_new();
}

sub _self {
    my ($class_self) = @_;
    return ref($class_self) ? $class_self : $g_self;
}

sub register {
    my ($class_self, $key, @components) = @_;
    my $self = $class_self->_self or return;
    push(@{$self->{$key}}, @components);
}

sub _registerSignalHandler {
    my ($class_self, $signame, $cb) = @_;
    my $self = $class_self->_self or return;
    $signame = uc($signame);
    $self->{signal_watchers}{$signame} = AnyEvent->signal(
        signal => $signame,
        cb => $cb,
    );
}

sub _handlerQuit {
    my ($class_self) = @_;
    my $self = $class_self->_self or return;
    foreach my $output (@{$self->{output}}) {
        eval {
            $output->saveStatuses();
        };
        if($@) {
            &bblog($@);
        }
    }
    foreach my $input (@{$self->{input}}) {
        eval {
            $input->saveTimeFile();
        };
        if($@) {
            &bblog($@);
        }
    }
    exit;
}

sub initComponents {
    my ($class_self) = @_;
    my $self = $class_self->_self or return;
    foreach my $output (@{$self->{output}}) {
        eval {
            $output->loadStatuses();
        };
        if($@) {
            &bblog(sprintf("WARNING: Cannot load statuses file for Output %s: %s", $output->getName, $@));
        }
    }
    foreach my $input (@{$self->{input}}) {
        eval {
            $input->loadTimeFile();
        };
        if($@) {
            &bblog(sprintf("WARNING: Cannot load time file for Input %s: %s", $input->getName, $@));
        }
    }
}

1;




