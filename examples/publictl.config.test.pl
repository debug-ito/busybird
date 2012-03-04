sub configBusyBird {
    our $twitter_worker = BusyBird::Worker::Twitter->new(
        traits   => [qw/API::REST API::Lists/],
        ssl => 1,
    );
    our $output = BusyBird::Output->new('default');
    our $timer = BusyBird::Timer->new(interval => 120);
    $timer->addInput(BusyBird::Input::Twitter::PublicTimeline->new(name => 'public_tl', worker => $twitter_worker, no_timefile => 1));
    $timer->addOutput($output);
    return ($output);
}

1;
