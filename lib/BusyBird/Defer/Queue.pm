package BusyBird::Defer::Queue;

use 5.006;
use strict;
use warnings;


our $VERSION = '0.01';


use Scalar::Util qw(blessed refaddr);
use Carp;
use BusyBird::Defer;

my %SELF = ();

sub new {
    my ($class, %params) = @_;
    my $self = bless {}, $class;
    $self->_init();
    $self->max_active(defined($params{max_active}) ? $params{max_active} : 1);
    return $self;
}

sub deferrize {
    my ($self, @childs) = @_;
    my $newone = blessed($self)->new(max_active => $self->max_active);
    $newone->do(@childs);
    return $newone;
}

sub DESTROY {
    my ($self) = @_;
    delete $SELF{refaddr($self)};
}

sub _init {
    my ($self) = @_;
    $self->original(BusyBird::Defer->new());
    $self->max_active(1);
    $self->cur_active(0);
    $self->jobqueue([]);
}

sub original {
    my ($self, $arg) = @_;
    $SELF{refaddr $self}{__original} = $arg if defined($arg);
    return $SELF{refaddr $self}{__original};
}

sub max_active {
    my ($self, $arg) = @_;
    $SELF{refaddr $self}{__max_active} = $arg if defined($arg);
    return $SELF{refaddr $self}{__max_active};
}

sub cur_active {
    my ($self, $arg) = @_;
    $SELF{refaddr $self}{__cur_active} = $arg if defined($arg);
    return $SELF{refaddr $self}{__cur_active};
}

sub jobqueue {
    my ($self, $arg) = @_;
    $SELF{refaddr $self}{__jobqueue} = $arg if defined($arg);
    return $SELF{refaddr $self}{__jobqueue};
}

sub done {
    my ($self, @results) = @_;

    ## If $self is given to another Defer's run() method as its
    ## parent, $self->done() is called without calling
    ## $self->run(). In this case, it just call $self->run() instead
    ## to start a new execution.

    return $self->run(undef, @results);
}

sub run {
    my ($self, @args) = @_;
    push(@{$self->jobqueue}, \@args);
    $self->_shift_run();
    return $self;
}

sub _shift_run {
    my ($self) = @_;
    return if $self->max_active > 0 && $self->cur_active >= $self->max_active;
    my $args_ref = shift(@{$self->jobqueue});
    return if !defined($args_ref);

    my $container = BusyBird::Defer->new();
    my $error_obj = undef;
    my $cloned_orig = $self->original->clone;
    $container->try();
    $container->do($cloned_orig);
    $container->catch(
        qr// => sub {
            my ($d, $err) = @_;
            $error_obj = $err;
            $d->done;
        },
    );
    $container->do(
        sub {
            my ($d, @args) = @_;
            $self->cur_active($self->cur_active - 1);
            $self->_shift_run();
            if(defined($error_obj)) {
                $d->throw($error_obj);
            }else {
                $d->done(@args);
            }
        }
    );
    $self->cur_active($self->cur_active + 1);
    %{$cloned_orig} = %{$self};
    eval {
        $container->run(@$args_ref);
    };
    if($@) {
        $self->cur_active($self->cur_active - 1);
        croak $@;
    }
}

sub clone {
    my ($self) = @_;
    my $clone = blessed($self)->new();
    $clone->original($self->original->clone());
    $clone->max_active($self->max_active);
    %$clone = %$self;
    return $clone;
}

## delegated methods
sub        do { my $self = shift; $self->original->       do(@_); return $self }
sub        if { my $self = shift; $self->original->       if(@_); return $self }
sub      else { my $self = shift; $self->original->     else(@_); return $self }
sub    end_if { my $self = shift; $self->original->   end_if(@_); return $self }
sub     while { my $self = shift; $self->original->    while(@_); return $self }
sub end_while { my $self = shift; $self->original->end_while(@_); return $self }
sub       try { my $self = shift; $self->original->      try(@_); return $self }
sub     catch { my $self = shift; $self->original->    catch(@_); return $self }
sub     throw { my $self = shift; $self->original->    throw(@_); return $self }
sub  continue { my $self = shift; $self->original-> continue(@_); return $self }
sub     break { my $self = shift; $self->original->    break(@_); return $self }



1; # End of BusyBird::Defer::Queue
