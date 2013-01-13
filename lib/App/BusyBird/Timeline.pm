package App::BusyBird::Timeline;

1;

=pod

=head1 NAME

App::BusyBird::Timeline - a timeline object in BusyBird

=head1 CLASS METHODS

=head1 OBJECT METHODS

=head2 $timeline->add_statuses($arrayref_of_statuses, [$callback->($added_num, $error)])

=head2 $timeline->confirm([$callback->($confirmed_num, $error)])

=head2 $timeline->get_statuses(%args)

=head2 $timeline->contains($arrayref_of_ids, $callback->($contained_ids, $not_contained_ids, $error))

=head2 $timeline->selector()

=head2 $storage = $timeline->get_status_storage()

=head1 AUTHOR

Toshio Ito C<< toshioito [at] cpan.org >>

=cut


