package BusyBird::Main::PSGI::View;

1;

__END__

=pod

=head1 NAME

BusyBird::Main::PSGI::View - view renderer for BusyBird::Main

=head1 DESCRIPTION

This is a view renderer object for L<BusyBird::Main>.

=head1 CLASS METHODS

=head2 $view = BusyBird::Main::PSGI::View->new(%args)

The constructor.

Fields in C<%args> are:

=over

=item C<main_obj> => L<BusyBird::Main> OBJECT (mandatory)

=back

=head1 OBJECT METHODS

=head2 $psgi_response = $view->response_notfound([$message])

Returns a "404 Not Found" page.

C<$message> is the message body, which is optional.

Return value C<$psgi_response> is a L<PSGI> response object.

=head2 $psgi_response = $view->response_json($http_code, $response_object)

Returns a response object whose content is a JSON-fomatted object.

C<$http_code> is the HTTP response code such as "200", "404" and "500".
C<$response_object> is a reference to an object.

Return value C<$psgi_response> is a L<PSGI> response object.
Its content is C<$response_object> formatted in JSON.

C<$response_object> must be encodable by L<JSON>.
Otherwise, it returns a L<PSGI> response with HTTP code of 500 (Internal Server Error).

If C<$http_code> is 200, C<$response_object> is a hash-ref and C<< $response_object->{error} >> does not exist,
C<< $response_object->{error} >> is automatically set to C<undef>, indicating the response is successful.

=head2 $psgi_response = $view->response_statuses(%args)

=over

=item C<statuses> => ARRAYREF_OF_STATUSES (semi-optional)

=item C<error> => STR (semi-optional)

=item C<format> => STR (mandatory)

Possible formats are:

=over

=item C<"html">

=item C<"json">

=back

=item C<timeline_name> => STR (mandatory)

=back

=head2 $psgi_response = $view->response_timeline($timeline_name)

=head1 AUTHOR

Toshio Ito C<< <toshioito [at] cpan.org> >>

=cut


