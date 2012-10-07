package BusyBird::Defer::Queue;

use 5.006;
use strict;
use warnings;


our $VERSION = '0.01';


use Scalar::Util qw(blessed refaddr);
use BusyBird::Defer;

my %SELF = ();

sub new {
    my ($class, %params) = @_;
    my $self = bless {}, $class;
    $self->_init();
    $self->max_active(defined($params{max_active}) ? $params{max_active} : 1);
    $self->try();
    return $self;
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
    $self->doneable(0);
}

sub original {
    my ($self, $arg) = @_;
    $SELF{refaddr $self}{__original} = $arg if defined($arg);
    return $SELF{refaddr $self}{__original};
}

sub doneable {
    my ($self, $arg) = @_;
    $SELF{refaddr $self}{__doneable} = $arg if defined($arg);
    return $SELF{refaddr $self}{__doneable};
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
    ## $self->run(). This is not good because we have a hook at run()
    ## method to control parallel execution. So $self->doneable
    ## attribute flag is used to detect call to done() without run(),
    ## and to force calling run() instead.
    
    if(!$self->doneable) {
        return $self->run(undef, @results);
    }
    return $self->original->done(@results);
}

sub run {
    my ($self, @args) = @_;
    push(@{$self->jobqueue}, \@args);
    $self->_shift_run();
}

sub _shift_run {
    my ($self) = @_;
    return if $self->max_active > 0 && $self->cur_active >= $self->max_active;
    my $args_ref = shift(@{$self->jobqueue});
    return if !defined($args_ref);
    
    my $clone = $self->clone;
    my $error_obj = undef;
    $clone->catch(
        qr// => sub {
            my ($d, $err) = @_;
            $error_obj = $err;
            $d->done;
        },
    );
    $clone->do(
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
    $clone->doneable(1);
    $self->cur_active($self->cur_active + 1);
    %{$clone->original} = %{$clone};
    $clone->original->run(@$args_ref);
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
sub        do { my $self = shift; return $self->original->       do(@_) }
sub        if { my $self = shift; return $self->original->       if(@_) }
sub      else { my $self = shift; return $self->original->     else(@_) }
sub    end_if { my $self = shift; return $self->original->   end_if(@_) }
sub     while { my $self = shift; return $self->original->    while(@_) }
sub end_while { my $self = shift; return $self->original->end_while(@_) }
sub       try { my $self = shift; return $self->original->      try(@_) }
sub     catch { my $self = shift; return $self->original->    catch(@_) }
sub     throw { my $self = shift; return $self->original->    throw(@_) }
sub  continue { my $self = shift; return $self->original-> continue(@_) }
sub     break { my $self = shift; return $self->original->    break(@_) }



1; # End of BusyBird::Defer::Queue
