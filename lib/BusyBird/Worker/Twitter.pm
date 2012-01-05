package BusyBird::Worker::Twitter;

use strict;
use warnings;
use POSIX qw(_exit);
use POE qw(Filter::Reference);
use Net::Twitter;
use BusyBird::Worker;
use Data::Dumper;

sub create {
    my ($class, %net_twitter_params) = @_;
    $net_twitter_params{traits} ||= [qw(OAuth API::REST API::Lists)];
    $net_twitter_params{ssl}    ||= 1;
    my $nt = Net::Twitter->new(%net_twitter_params); # Imported into "Program" closure
    return BusyBird::Worker->new(
        Program => sub {
            POE::Kernel->stop();
            my $input_str;
            {
                local $/ = undef;
                $input_str = <STDIN>;
            }
            my $filter = POE::Filter::Reference->new();
            my $command_objs = $filter->get([$input_str]);
            ## print STDERR (Dumper($command_objs));
            ## _exit(0);
            
            my $output_obj = [];
            foreach my $command (@$command_objs) {
                my ($method_name, $arg_hash_ref) = ($command->{method}, $command->{arg});
                if(!$nt->can($method_name)) {
                    printf STDERR ("Method %s is undefined on Net::Twitter.\n", $method_name);
                    next;
                }
                my $ret;
                eval {
                    $ret = $nt->$method_name($arg_hash_ref);
                };
                if($@) {
                    printf STDERR ("Error: Net::Twitter::%s: %s\n", $method_name, $@);
                    next;
                }
                push(@$output_obj, $ret);
            }
            my $serialized_chunks = $filter->put($output_obj);
            foreach my $chunk (@$serialized_chunks) {
                print $chunk;
            }
        },
        StdinFilter  => POE::Filter::Reference->new(),
        StdoutFilter => POE::Filter::Reference->new(),
    );
}


1;

