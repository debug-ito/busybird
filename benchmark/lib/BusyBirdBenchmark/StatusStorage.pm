package BusyBirdBenchmark::StatusStorage;
use strict;
use warnings;
use BusyBird::Util qw(set_param);
use BusyBird::Timeline;
use List::Util qw(shuffle);
use Timer::Simple;
use Storable qw(dclone);

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
    $self->set_param(\%args, 'initial_status_num', 2000);
    $self->set_param(\%args, 'insert_status_num', 20);
    $self->set_param(\%args, 'insert_num', 10);
    $self->set_param(\%args, 'get_acked_status_num', 20);
    $self->_init();
    return $self;
}

sub _init {
    my ($self) = @_;
    $self->{timelines} = [map {
        BusyBird::Timeline->(name => "tl_$_", storage => $self->{storage});
    } 0 .. ($self->{timeline_num} - 1)];
    $self->{statuses_to_add} = [map { dclone($SAMPLE_STATUS) } 1..$self->{insert_status_num}];
    my @insert_timeline_indice = shuffle map { ($_) x $self->{initial_status_num} } 0 .. ($self->{timeline_num} - 1);
    foreach my $timeline_index (@insert_timeline_indice) {
        $self->{timelines}[$timeline_index]->add($SAMPLE_STATUS, sub {
            my ($error, $num) = @_;
            die "insert error: $error" if defined $error;
            die "insert error: num of insert = $num (!= 1)" if $num != 1;
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

sub run_once {
    my ($self) = @_;
    my %result = (
        add => undef,
        get_unacked => undef,
        ack => undef,
        get_acked => undef
    );
    my $timeline = $self->{timelines}[int(rand($self->{timeline_num}))];
    my $timer = Timer::Simple->new;
    foreach (1 .. $self->{insert_num}) {
        $timeline->add($self->{statuses_to_add}, sub {
            my ($e, $num) = @_;
            die "add error: $e" if not defined $e;
            die "add error: add num != $self->{insert_status_num}" if $num != $self->{insert_status_num};
        });
    }
    $result{add} = $timer->elapsed / $self->{insert_num};
    
    my $exp_get_unacked = $self->{insert_num} * $self->{insert_status_num};
    my @unacked_ids = ();
    $timer = Timer::Simple->new;
    $timeline->get_statuses(ack_state => 'unacked', count => 'all', callback => sub {
        my ($e, $statuses) = @_;
        die "get unacked error: $e" if not defined $e;
        my $got_num = scalar(@$statuses);
        die "get unacked error: got $got_num but expected $exp_get_unacked" if $got_num != $exp_get_unacked;
        $result{get_unacked} = $timer->elapsed;
        @unacked_ids = map { $_->{id} } @$statuses;
    });

    $timer = Timer::Simple->new;
    $timeline->ack_statuses(ids => \@unacked_ids, callback => sub {
        my ($e, $num) = @_;
        die "ack error: $e" if defined $e;
        die "ack error: ack $num statuses but expected $exp_get_unacked" if $num != $exp_get_unacked;
        $result{ack} = $timer->elapsed;
    });

    $timer = Timer::Simple->new;
    $timeline->get_statuses(
        ack_state => 'unacked', count => $self->{get_acked_status_num}, max_id => $unacked_ids[-1],
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

1;

