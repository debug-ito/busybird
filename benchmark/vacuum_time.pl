use strict;
use warnings;
use Getopt::Long qw(:config bundling no_ignore_case);
use Pod::Usage;
use Try::Tiny;
use JSON;
use DBI;
use BusyBird::StatusStorage::SQLite;
use BusyBird::Timeline;
use Timer::Simple;
use Storable qw(dclone);

sub get_delete_count {
    my ($db_filename) = @_;
    my $dbh = DBI->connect("dbi:SQLite:dbname=$db_filename", "","", {
        RaiseError => 1, PrintError => 0, AutoCommit => 1
    });
    my $record = $dbh->selectrow_arrayref(
        "SELECT delete_count FROM delete_counts WHERE delete_count_id = ?",
        undef, 0
    );
    die "cannot fetch delete count" if not defined $record;
    return $record->[0];
}

my $status = {
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

my $AUTO_REMOVE = 0;
my $TIMELINE_NUM = 1;
my $STATUS_COUNT_ONE_TIME = 200;
my $PUT_NUM = 40;
my $STORAGE_FILENAME;

try {
    GetOptions(
        'R' => \$AUTO_REMOVE,
        't=i' => \$TIMELINE_NUM,
        'c=i' => \$STATUS_COUNT_ONE_TIME,
        'N=i' => \$PUT_NUM,
    );
    $STORAGE_FILENAME = $ARGV[0];
    die "No STORAGE_FILENAME specified.\n" if not defined $STORAGE_FILENAME;
}catch {
    my $e = shift;
    warn "$e\n";
    pod2usage(-verbose => 2, -noperldoc => 1);
    exit 0;
};

if(-r $STORAGE_FILENAME) {
    if(!$AUTO_REMOVE) {
        die "$STORAGE_FILENAME already exists. Remove that manually or use -R option.\n";
    }
    unlink($STORAGE_FILENAME) or die "cannot remove $STORAGE_FILENAME";
    print STDERR "$STORAGE_FILENAME is removed.\n";
}

my $storage = BusyBird::StatusStorage::SQLite->new(
    path => $STORAGE_FILENAME,
    vacuum_on_delete => 0,
);

my @timelines = map { BusyBird::Timeline->new(name => "timeline_$_", storage => $storage) } 1..$TIMELINE_NUM;

my @statuses = (map { dclone($status) } 1..$STATUS_COUNT_ONE_TIME);

my $timer = Timer::Simple->new;
print STDERR "Start putting: ";
foreach my $round (1 .. $PUT_NUM) {
    foreach my $timeline (@timelines) {
        $timeline->add(\@statuses, sub {
            my ($error, $num) = @_;
            die "put error: $error" if defined($error);
            if($num != $STATUS_COUNT_ONE_TIME) {
                die("Timeline " . $timeline->name . ": $num (!= $STATUS_COUNT_ONE_TIME) inserted. something is wrong.");
            }
        });
    }
    print STDERR ".";
}
print STDERR "\n";
print STDERR "Put completes in $timer\n";

foreach my $timeline (@timelines) {
    $timeline->get_unacked_counts(callback => sub {
        my ($error, $unacked_counts) = @_;
        die "get unacked counts error: $error" if defined $error;
        print STDERR "Timeline ", $timeline->name, ": ", $unacked_counts->{total}, " unacked statuses\n";
    });
}

print STDERR "Do vacuum\n";
$timer = Timer::Simple->new;
$storage->vacuum();
print STDERR "Vacuum completes in $timer\n";

__END__

=pod

=head1 NAME

vacuum_time.pl - Measure how long BusyBird::StatusStorage::SQLite::vacuum() takes

=head1 SYNOPSIS

    $ perl vacuum_time.pl [OPTIONS] SQLITE_FILENAME

=head1 DESCRIPTION

SQLITE_FILENAME is the SQLite database filename for the test.
It first populates some statuses into the storage, then it calls vacuum() and measures its time.

=head1 OPTIONS

=over

=item -R

Optional. If set, the file SQLITE_FILENAME is removed before the test.
Otherwise, it aborts the script if SQLITE_FILENAME already exists.

=item -t TIMELINE_NUM

Optional (default: 1). The number of timelines it will create in the storage.

=item -c STATUS_COUNT_ONE_TIME

Optional (default: 200).
The number of statuses inserted into each timeline for a single call of put_statuses() method.

=item -N PUT_NUM

Optional (default: 40).
The number of calls of put_statuses() method for each timeline.
Thus, (STATUS_COUNT_ONE_TIME * PUT_NUM) statuses will be inserted into each timeline before vacuum().

=back

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut
