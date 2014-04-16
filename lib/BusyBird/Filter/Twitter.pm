package BusyBird::Filter::Twitter;
use strict;
use warnings;

1;
__END__

=pod

=head1 NAME

BusyBird::Filter::Twitter - filters for statuses imported from Twitter

=head1 SYNOPSIS

    write synopsis (using 'BusyBird' module)

=head1 DESCRIPTION

This module provides filters that you should apply to statuses imported from Twitter.
Basically it does the following transformation to the input statuses.

=over

=item *

Convert status IDs to include the source of the statuses.
This prevents ID conflict between statuses from different sources.

=item *

Add BusyBird-specific fields to the statuses.

=item *

Normalize status objects from Search API v1.0.

=item *

Transform text content so that L<BusyBird> can render it appropriately.

=back

Note that this module does not help you import statuses from Twitter.
For that purpose, I recommend L<Net::Twitter::Loader>.

=head1 EXPORTED FUNCTIONS

All functions in this section are exported by default.

These functions generate a filter, a subroutine reference to process an array-ref of statuses
and return the result.

    $result_arrayref = $filter->($arrayref_of_statuses)

You can directly pass the filter to L<BusyBird::Timeline>'s C<add_filter()> method.

    $timeline->add_filter(filter_twitter_all);

All filters are non-destructive. That is, they won't modify input statuses. Transformation is done to their clones.

=head2 $filter = filter_twitter_all([$api_url])

Generates a filter that applies all filters described below to the given statuses.

Argument C<$api_url> is optional. See C<filter_twitter_status_id()> function below.

=head2 $filter = filter_twitter_search_status()

Generates a filter that transforms a status object returned by Twitter's Search API v1.0 into something more like a normal status object.

=head2 $filter = filter_twitter_status_id([$api_url])

Generates a filter that transforms a status's ID fields so that they include API URL of the source.
This transformation is recommended when you load statuses from multiple sources, e.g. twitter.com and loadaverage.org.

Argument C<$api_url> is optional. By default it is C<"https://api.twitter.com/1.1/">.
You should set it appropriately if you import statuses from other sites.

The original IDs are saved under C<< $transformed_status->{busybird}{original} >>


=head2 $filter = filter_twitter_unescape()

Generates a filter that unescapes some HTML entities in the status's text field.

HTML-unescape is necessary because twitter.com automatically HTML-escapes some special characters,
AND L<BusyBird> also HTML-escapes status texts when it renders them.
This results in double HTML-escapes.

The transformation changes the status's text length.
C<"indices"> fields in the status's L<Twitter Entities|https://dev.twitter.com/docs/platform-objects/entities> are
adjusted appropriately.

The transformtion is applied recursively to the status's C<retweeted_status>, if any.


=head1 SEE ALSO

=over

=item *

L<Net::Twitter>

=item *

L<Net::Twitter::Lite>

=item *

L<Net::Twitter::Loader>

=back

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut
