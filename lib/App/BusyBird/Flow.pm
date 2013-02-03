package App::BusyBird::Flow;
use strict;
use warnings;
use Async::Queue;
use App::BusyBird::Log;
use CPS qw(kforeach);
use Carp;
use Scalar::Util qw(weaken);

sub new {
    my ($class) = @_;
    my $self = bless {
        filters => [],
    }, $class;
    $self->{queue} = $self->_create_queue();
    return $self;
}

sub _create_queue {
    my ($self) = @_;
    weaken $self;
    return Async::Queue->new(concurrency => 1, worker => sub {
        my ($data, $done) = @_;
        kforeach $self->{filters}, sub {
            my ($filter, $knext) = @_;
            $filter->($data, sub {
                my ($result) = @_;
                if(ref($result) && ref($result) eq 'ARRAY') {
                    $data = $result;
                }else {
                    bblog('warn', 'The filter did not return an array-ref. Ignored.');
                }
                $knext->();
            });
        }, sub {
            $done->($data);
        };
    });
}

sub add {
    my ($self, $async_filter) = @_;
    if($self->{queue}->running) {
        croak "You cannot add a filter while there is a status running in it."
    }
    push(@{$self->{filters}}, $async_filter);
}

sub execute {
    my ($self, $data, $callback) = @_;
    $self->{queue}->push($data, $callback);
}


our $VERSION = '0.01';

1;

=pod

=head1 NAME

App::BusyBird::Flow - CPS data flow with concurrency regulation

=head1 VERSION

0.01

=head1 SYNOPSIS

    use App::BusyBird::Flow;
    
    my $flow = App::BusyBird::Flow->new();
    
    $flow->add(sub {
        my ($data, $done) = @_;
        my $new_data = transform($data);
        $done->($new_data);
    });
    
    $flow->add(sub {
        my ($data, $done) = @_;
        transform_async($data, sub {
            my $new_data = shift;
            $done->($new_data);
        });
    });
    
    $flow->execute('some_data', sub {
        my ($result_data) = @_;
        print "Result: $result_data\n";
    });

=head1 DESCRIPTION

This module takes CPS (continuation-passing style) subroutines as 'filters'
and executes them sequentially to a given data.
The result of a filter is given to the next filter, so the data flow is in
so-called 'waterfall' model.
In the data flow, the number of data flowing simultaneously is limited.
If additional data is pushed to the flow, it will be delayed in a queue that is built in the flow.

This module is a part of L<App::BusyBird::Timeline>.
For now, it is not meant to be used individually.

=head1 CLASS METHODS

=head2 $flow = App::BusyBird::Flow->new()

Creates the flow object.

=head1 OBJECT METHODS

=head2 $flow->add($filter->($data, $done))

Add a filter to the C<$flow>.

=head2 $flow->execute($data, $finish_callback->($result))

Execute the flow on the C<$data>.
The result will given to C<$finish_callback>.

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut




