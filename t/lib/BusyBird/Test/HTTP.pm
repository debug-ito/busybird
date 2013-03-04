package BusyBird::Test::HTTP;
use strict;
use warnings;
use BusyBird::Util 'set_param';
use HTTP::Request;
use Test::More;
use Test::Builder;
use JSON qw(from_json);

sub new {
    my ($class, %params) = @_;
    my $self = bless {}, $class;
    $self->set_param(\%params, 'requester', undef, 1);
    return $self;
}

sub get_json_ok {
    my ($self, $request_url, $res_code_like, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    return $self->request_json_ok('GET', $request_url, undef, $res_code_like, $msg);
}

sub post_json_ok {
    my ($self, $request_url, $content, $res_code_like, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    return $self->request_json_ok('POST', $request_url, $content, $res_code_like, $msg);
}

sub request_json_ok {
    my ($self, $method, $request_url, $content, $res_code_like, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $res = $self->{requester}->(HTTP::Request->new($method, $request_url, undef, $content));
    if(defined $res_code_like) {
        like($res->code, $res_code_like, $msg);
    }
    return from_json($res->decoded_content(raise_error => 1));
}

1;
