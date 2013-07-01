package BusyBirdBenchmark::StatusStorage;
use strict;
use warnings;
use BusyBird::Util qw(set_param);
use BusyBird::Timeline;
use List::Util qw(shuffle);
use Timer::Simple;
use Storable qw(dclone);
use JSON;
use Statistics::Descriptive;
use IO::Handle;

our $SAMPLE_STATUS = {
    'source' => '<a href="http://www.google.com/" rel="nofollow">debug_ito writer</a>',
    'retweeted' => JSON::false,
    'favorited' => JSON::false,
    'coordinates' => undef,
    'place' => undef,
    'retweet_count' => 0,
    'entities' => {
        'hashtags' => [
            {
                'text' => 'test',
                'indices' => [
                    106,
                    111
                ]
            }
        ],
        'user_mentions' => [
            {
                'name' => 'Toshio Ito',
                'id' => 797588971,
                'id_str' => '797588971',
                'indices' => [
                    77,
                    87
                ],
                'screen_name' => 'debug_ito'
            }
        ],
        'symbols' => [],
        'urls' => [
            {
                'display_url' => 'google.co.jp',
                'expanded_url' => 'http://www.google.co.jp/',
                'url' => 'http://t.co/dNlPhACDcS',
                'indices' => [
                    44,
                    66
                ]
            }
        ]
    },
    'truncated' => JSON::false,
    'in_reply_to_status_id_str' => undef,
    'created_at' => 'Thu May 16 12:56:23 +0000 2013',
    'contributors' => undef,
    'text' => "\x{e3}\x{81}\x{a6}\x{e3}\x{81}\x{99}\x{e3}\x{81}\x{a8} &lt;\"&amp;hearts;&amp;&amp;hearts;\"&gt; http://t.co/dNlPhACDcS &gt;\"&lt; \@debug_ito &amp; &amp; &amp; #test",
    'in_reply_to_user_id' => undef,
    'user' => {
        'friends_count' => 12,
        'follow_request_sent' => JSON::false,
        'profile_background_image_url_https' => 'https://si0.twimg.com/images/themes/theme1/bg.png',
        'profile_image_url' => 'http://a0.twimg.com/sticky/default_profile_images/default_profile_4_normal.png',
        'profile_sidebar_fill_color' => 'DDEEF6',
        'entities' => {
            'url' => {
                'urls' => [
                    {
                        'display_url' => "metacpan.org/author/TOSHIOI\x{e2}\x{80}\x{a6}",
                        'expanded_url' => 'https://metacpan.org/author/TOSHIOITO',
                        'url' => 'https://t.co/ZyZqxH0g',
                        'indices' => [
                            0,
                            21
                        ]
                    }
                ]
            },
            'description' => {
                'urls' => []
            }
        },
        'profile_background_color' => 'C0DEED',
        'notifications' => JSON::false,
        'url' => 'https://t.co/ZyZqxH0g',
        'id' => 797588971,
        'is_translator' => JSON::false,
        'following' => JSON::false,
        'screen_name' => 'debug_ito',
        'lang' => 'ja',
        'location' => '',
        'followers_count' => 1,
        'name' => 'Toshio Ito',
        'statuses_count' => 10,
        'description' => 'Perl etc.',
        'favourites_count' => 0,
        'profile_background_tile' => JSON::false,
        'listed_count' => 0,
        'contributors_enabled' => JSON::false,
        'profile_link_color' => '0084B4',
        'profile_image_url_https' => 'https://si0.twimg.com/sticky/default_profile_images/default_profile_4_normal.png',
        'profile_sidebar_border_color' => 'C0DEED',
        'created_at' => 'Sun Sep 02 05:33:08 +0000 2012',
        'utc_offset' => 32400,
        'verified' => JSON::false,
        'profile_background_image_url' => 'http://a0.twimg.com/images/themes/theme1/bg.png',
        'default_profile' => JSON::true, ##bless( do{\(my $o = 1)}, 'JSON::PP::Boolean' ),
        'protected' => JSON::false,
        'id_str' => '797588971',
        'profile_text_color' => '333333',
        'default_profile_image' => JSON::true,
        'time_zone' => 'Irkutsk',
        'geo_enabled' => JSON::false,
        'profile_use_background_image' => JSON::true,
    },
    ## 'id' => '335015876287950848',
    'in_reply_to_status_id' => undef,
    'geo' => undef,
    'lang' => 'ja',
    'possibly_sensitive' => JSON::false,
    'in_reply_to_user_id_str' => undef,
    ## 'id_str' => '335015876287950848',
    'in_reply_to_screen_name' => undef,
    'favorite_count' => 0
};

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        timelines => undef,
        statuses_to_add => undef,
    }, $class;
    $self->set_param(\%args, 'storage', undef, 1);
    $self->set_param(\%args, 'timeline_num', 3);
    $self->set_param(\%args, 'initial_insert_status_num', 20);
    $self->set_param(\%args, 'initial_insert_num', 100);
    $self->set_param(\%args, 'insert_status_num', 20);
    $self->set_param(\%args, 'insert_num', 10);
    $self->set_param(\%args, 'get_acked_status_num', 20);
    $self->_init();
    return $self;
}

sub _init {
    my ($self) = @_;
    $self->{timelines} = [map {
        BusyBird::Timeline->new(name => "tl_$_", storage => $self->{storage});
    } 0 .. ($self->{timeline_num} - 1)];
    $self->{statuses_to_add} = [map { dclone($SAMPLE_STATUS) } 1..$self->{insert_status_num}];

    my @initial_statuses_to_add = map { dclone($SAMPLE_STATUS) } 1..$self->{initial_insert_status_num};
    my @insert_timeline_indice = shuffle map { ($_) x $self->{initial_insert_num} } 0 .. ($self->{timeline_num} - 1);
    foreach my $timeline_index (@insert_timeline_indice) {
        $self->{timelines}[$timeline_index]->add(\@initial_statuses_to_add, sub {
            my ($error, $num) = @_;
            die "initial insert error: $error" if defined $error;
            if($num != $self->{initial_insert_status_num}) {
                die "initial insert error: num of insert = $num, but expected $self->{initial_insert_status_num}";
            }
        });
    }
    foreach my $timeline (@{$self->{timelines}}) {
        $timeline->ack_statuses(callback => sub {
            my ($e, $num) = @_;
            die "ack error: $e" if defined $e;
            die "ack error: zero ack" if $num == 0;
        });
    }
}

sub benchmark {
    my ($class, $options, $targets) = @_;
    $options ||= {};
    $targets ||= {};
    my $output = delete $options->{output} || IO::Handle->new_from_fd(fileno(STDOUT), "w");
    die "Cannot open the output" if !$output;
    my $run_count = delete $options->{run_count} || 100;

    my %results_for_step = ();
    foreach my $target_name (keys %$targets) {
        my $target = $targets->{$target_name};
        print STDERR "$target_name: start initialization...\n";
        my $bench = $class->new(%$options, storage => $target);
        print STDERR "$target_name: initialization complete\n";
        print STDERR "$target_name: ";
        my $stats = $bench->get_statistics($run_count, sub {
            my ($index) = @_;
            if(($index + 1) % int($run_count / 10) == 0) {
                print STDERR "*";
            }
        });
        print STDERR "\n";
        print STDERR "$target_name: measurement finished.\n";
        foreach my $stat_key (sort {$a cmp $b} keys %$stats) {
            $results_for_step{$stat_key}{$target_name} = $stats->{$stat_key};
        }
    }
    
    $output->autoflush(1);
    $output->print(qq{##label count median 10percentile min max 90percentile\n});
    foreach my $step_key (sort {$a cmp $b} keys %results_for_step) {
        my $targets = $results_for_step{$step_key};
        foreach my $target_key (sort {$a cmp $b} keys %$targets) {
            my $stat = $targets->{$target_key};
            my $label = "$target_key / $step_key";
            my $low_percentile = scalar($stat->percentile(10));
            my $high_percentile = scalar($stat->percentile(90));
            $low_percentile = "1/0" if not defined $low_percentile;
            $high_percentile = "1/0" if not defined $high_percentile;
            $output->printf('"%s" %d %e %e %e %e %e',
                            $label, $stat->count,
                            $stat->median, $low_percentile,
                            $stat->min, $stat->max, $high_percentile);
            $output->print("\n");
        }
    }
}

sub run_once {
    my ($self) = @_;
    my %result = (
        add => undef,
        get_count => undef,
        get_unacked => undef,
        ack => undef,
        get_acked => undef
    );
    my $timeline = $self->{timelines}[int(rand($self->{timeline_num}))];
    my $timer = Timer::Simple->new;
    foreach (1 .. $self->{insert_num}) {
        $timeline->add($self->{statuses_to_add}, sub {
            my ($e, $num) = @_;
            die "add error: $e" if defined $e;
            die "add error: add num != $self->{insert_status_num}" if $num != $self->{insert_status_num};
        });
    }
    $result{add} = $timer->elapsed / $self->{insert_num};
    
    my $exp_unacked_count = $self->{insert_num} * $self->{insert_status_num};
    $timer = Timer::Simple->new;
    $timeline->get_unacked_counts(callback => sub {
        my ($e, $unacked_counts) = @_;
        die "get unacked counts error: $e" if defined $e;
        if($unacked_counts->{total} != $exp_unacked_count) {
            die "get unacked counts error: total unacked count = $unacked_counts->{total}, but expected $exp_unacked_count";
        }
        $result{get_count} = $timer->elapsed;
    });
    
    my @unacked_ids = ();
    $timer = Timer::Simple->new;
    $timeline->get_statuses(ack_state => 'unacked', count => 'all', callback => sub {
        my ($e, $statuses) = @_;
        die "get unacked error: $e" if defined $e;
        my $got_num = scalar(@$statuses);
        die "get unacked error: got $got_num but expected $exp_unacked_count" if $got_num != $exp_unacked_count;
        $result{get_unacked} = $timer->elapsed;
        @unacked_ids = map { $_->{id} } @$statuses;
    });

    $timer = Timer::Simple->new;
    $timeline->ack_statuses(ids => \@unacked_ids, callback => sub {
        my ($e, $num) = @_;
        die "ack error: $e" if defined $e;
        die "ack error: ack $num statuses but expected $exp_unacked_count" if $num != $exp_unacked_count;
        $result{ack} = $timer->elapsed;
    });

    $timer = Timer::Simple->new;
    $timeline->get_statuses(
        ack_state => 'acked', count => $self->{get_acked_status_num}, max_id => $unacked_ids[-1],
        callback => sub {
            my ($e, $statuses) = @_;
            die "get acked error: $e" if defined $e;
            my $got_num = scalar(@$statuses);
            if($got_num != $self->{get_acked_status_num}) {
                die "get acked error: got $got_num statuses but expected $self->{get_acked_status_num}";
            }
            $result{get_acked} = $timer->elapsed;
        }
    );

    return \%result;
}

sub get_statistics {
    my ($self, $count, $progress) = @_;
    my %stats = ();
    $progress ||= sub {};
    foreach my $iteration_index (0 .. ($count - 1)) {
        $progress->($iteration_index);
        my $ret = $self->run_once();
        foreach my $key (keys %$ret) {
            if(!defined($stats{$key})) {
                $stats{$key} = Statistics::Descriptive::Full->new;
            }
            $stats{$key}->add_data($ret->{$key});
        }
    }
    return \%stats;
}

1;

__END__

=pod

=head1 NAME

BusyBirdBenchmark::StatusStorage - benchmark utility class for StatusStorages

=head1 SYNOPSIS

Benchmark a single storage.

    my $bench = BusyBirdBenchmark::StatusStorage->new(
        storage => BusyBird::StatusStorage::SQLite->new(path => ':memory:'),
    );
    
    my $ret = $bench->run_once();
    foreach my $key (%$ret) {
        print "$key : $ret->{$key}\n";
    }

Or, benchmark bunch of status storages.

    BusyBirdBenchmark::StatusStorage->benchmark(
        { timeline_num => 5, run_count => 200 },
        {
            memory     => BusyBird::StatusStorage::Memory->new,
            sqlite_mem => BusyBird::StatusStorage::SQLite->new(path => ':memory:'),
        }
    );

=head1 DESCRIPTION

This is a helper module to do benchmarks for L<BusyBird::StatusStorage> implementations.

The benchmark is done in the following procedure.

=over

=item 1.

Initially it populates timelines in the given storage.

=item 2.

It picks up a timeline randomly.

=item 3.

It inserts some unacked statuses to the timeline.
It measures the time the storage takes to insert all the statuses.

=item 4.

It gets the unacked counts of the timeline.
It measures the time the storage takes to return the counts.

=item 5.

It gets all the unacked statuses just inserted.
It measures the time the storage takes to return the statuses.

=item 6.

It acks all the unacked statuses just inserted by explicitly calling C<< ack_statuses(ids => \@ids ...) >>.
It measures the time the storage takes to complete the acking.

=item 7.

It gets some acked statuses below the statuses just inserted by calling C<< get_statuses(max_id => $bottom_id ...) >>.
It measures the time the storage takes to return the statuses.

=item 8.

Repeat the steps 2 - 7.

=back

=head1 CLASS METHODS

=head2 $bench = BusyBirdBenchmark::StatusStorage->new(%args)

The constructor. It runs the step 1 explained in the L</DESCRIPTION> section.

Fields in C<%args> are:

=over

=item C<storage> => STATUS_STORAGE (mandatory)

The L<BusyBird::StatusStorage> object to be benchmarked.
The storage should be empty.

=item C<timeline_num> => INT (optional, default: 3)

Number of timelines it creates for benchmark.

=item C<initial_insert_status_num> => INT (optional, default: 20)

Number of statuses inserted to a timeline by a single call to C<< add_statuses() >> during the initialization phase (step 1).

=item C<initial_insert_num> => INT (optional, default: 100)

Number of status insertions to a timeline during the initialization phase (step 1).
The total number of statuses inserted to a timeline is thus C<< initial_insert_status_num * initial_insert_num >>.

=item C<insert_status_num> => INT (optinal, default: 20)

Number of statuses inserted to a timeline by a single call to C<< add_statuses() >> during the measurement phase (step 3).

=item C<insert_num> => INT (optional, default: 10)

Number of status insertions to a timeline during the measurement phase (step 3).
The total number of statuses inserted to a timeline is thus C<< insert_status_num * insert_num >>.

=item C<get_acked_status_num> => INT (optional, default: 20)

Number of statuses obtained from a timeline in step 7.

=back

=head2 BusyBirdBenchMark::StatusStorage->benchmark($options, $targets)

Benchmark multiple status storages and prints the results.

C<$options> is a hash-ref.
Its content is directly passed to C<new()> method, though C<storage> field is ignored.
In addition, it accepts the following fields.

=over

=item C<run_count> => INT (optional, default: 100)

Number of executions of steps 2 - 7 for each target status storage.
This is passed to C<get_statistics()> method.

=item C<output> => IO::Handle object (optional, default: STDOUT)

An L<IO::Handle> object that it will prints the results to.

=back

C<$targets> is also a hash-ref that contains L<BusyBird::StatusStorage> to be tested.
Its value is the testee L<BusyBird::StatusStorage> object, and its key is an arbitrary name for the storage.

=head1 OBJECT METHODS

=head2 $result = $bench->run_once()

Runs the steps 2 - 7 once, and returns the measured time.

The steps executed by C<run_once()> is more or less the same as the ones the browser would take when it accesses to a timeline.

The C<$result> is a hash-ref containing following values.

=over

=item C<add> => NUMBER

Time in seconds it took to complete one insertion in step 3. (not time to do ALL insertion)

=item C<get_count> => NUMBER

Time in seconds it took to return the unacked counts in step 4.

=item C<get_unacked> => NUMBER

Time in seconds it took to do step 5.

=item C<ack> => NUMBER

Time in seconds it took to do step 6.

=item C<get_acked> => NUMBER

Time in seconds it took to do step 7.

=back

=head2 $stats = $bench->get_statistics($count, [$progress])

Runs C<run_once()> method C<$count> times and returns all results in a hash-ref of L<Statistics::Descriptive::Full> objects.

The optional parameter C<$progress> is a subroutine reference that is called before every call to C<run_once()>.
The iteration index is passed to C<$progress> as in

    $progress->($index)

where C<$index> is zero at the first call.

The return value C<$stats> is a hash-ref with the same struture as the one returned by C<run_once()>.
The defference is that values for C<$stats> are L<Statistics::Descriptive::Full> objects containing C<$count> values for each measurement.

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut
