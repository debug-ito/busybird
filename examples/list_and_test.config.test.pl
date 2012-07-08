use BusyBird::Worker::Twitter;
use BusyBird::Timer;
use BusyBird::Input;
use BusyBird::Output;
use BusyBird::HTTPD;

sub configBusyBird {
    my $script_dir = shift;
    my $twitter_worker = BusyBird::Worker::Twitter->new(
        traits   => [qw/API::REST API::Lists/],
        ssl => 1,
    );
    my $timer = BusyBird::Timer->new(interval => 120);
    my $input  = BusyBird::Input->new(
        driver => 'BusyBird::InputDriver::Twitter::List',
        name => 'tv_networks', worker => $twitter_worker,
        owner_name => 'shoflowapp', list_slug_name => 'networks'
    );

    my $fast_timer = BusyBird::Timer->new(interval => 30);
    my $test_input = BusyBird::Input->new(
        driver => 'BusyBird::InputDriver::Test',
        name => 'test', no_timefile => 1
    );

    my $output = BusyBird::Output->new(name => 'default');
    
    $timer->c($input)->c($output)->c(BusyBird::HTTPD->instance);
    $fast_timer->c($test_input)->c($output);
    BusyBird::HTTPD->start(static_root => $script_dir . "/resources/httpd/");
}

1;
