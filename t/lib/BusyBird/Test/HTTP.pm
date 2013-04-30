package BusyBird::Test::HTTP;
use strict;
use warnings;
use BusyBird::Util 'set_param';
use HTTP::Request;
use Test::More;
use Test::Builder;
use JSON qw(from_json);
use HTML::TreeBuilder 5 -weak;
use HTML::TreeBuilder::XPath;


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
    my $self = shift;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    return from_json($self->request_ok(@_));
}

sub request_ok {
    my ($self, $method, $request_url, $content, $res_code_like, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $res = $self->{requester}->(HTTP::Request->new($method, $request_url, undef, $content));
    if(defined $res_code_like) {
        like($res->code, $res_code_like, $msg);
    }
    return $res->decoded_content(raise_error => 1);
}

sub request_htmltree_ok {
    my ($self, $method, $request_url, $content, $res_code_like, $msg) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $res = $self->request_ok($method, $request_url, $content, $res_code_like, $msg);
    return HTML::TreeBuilder::XPath->new_from_content($res);
}

1;
