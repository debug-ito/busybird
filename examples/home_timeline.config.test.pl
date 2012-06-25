use BusyBird::Timer;
use BusyBird::Input;
use BusyBird::Output;
use BusyBird::Worker::Twitter;
use BusyBird::HTTPD;

sub configBusyBird {
    my $script_dir = shift;
    my $tworker = BusyBird::Worker::Twitter->new(
        traits   => [qw/OAuth API::REST API::Lists API::Search/],
        consumer_key        => 'YOUR_CONSUMER_KEY_HERE',
        consumer_secret     => 'YOUR_CONSUMER_SECRET_HERE',
        access_token        => 'YOUR_TOKEN_HERE',
        access_token_secret => 'YOUR_TOKE_SECRET_HERE',
        ssl => 1,
    );
    my $t_timer = BusyBird::Timer->new(interval => 120);
    my $t_input = BusyBird::Input->new(
        driver => 'BusyBird::InputDriver::Twitter::HomeTimeline',
        name => 'home', worker => $tworker,
    );
    
    my $output = BusyBird::Output->new(name => 'default');
    

    BusyBird::HTTPD->init();
    BusyBird::HTTPD->config(static_root => $script_dir . "/resources/httpd/");

    $t_timer->c($t_input)->c($output);
    $output->c(BusyBird::HTTPD->instance);
    
    BusyBird::HTTPD->start();
}

