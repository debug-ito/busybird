use strict;
use warnings;
use Test::More;
use Test::Builder;
use BusyBird::Main;
use BusyBird::Log;
use BusyBird::StatusStorage::Memory;
use JSON qw(decode_json);

BEGIN {
    use_ok("BusyBird::Main::PSGI::View");
}

$BusyBird::Log::Logger = undef;

sub test_psgi_response {
    my ($psgi_res, $exp_code, $label) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is(ref($psgi_res), "ARRAY", "$label: top array-ref OK");
    is($psgi_res->[0], $exp_code, "$label: status code OK");
    is(ref($psgi_res->[1]), "ARRAY", "$label: header array-ref OK");
    is(ref($psgi_res->[2]), "ARRAY", "$label: content array-ref OK");
}

sub test_json_response {
    my ($psgi_res, $exp_code, $exp_obj, $label) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    test_psgi_response($psgi_res, $exp_code, $label);
    my $got_obj = decode_json(join("", @{$psgi_res->[2]}));
    is_deeply($got_obj, $exp_obj, "$label: json object OK");
}

{
    my $main = BusyBird::Main->new;
    $main->set_config(
        default_status_storage => BusyBird::StatusStorage::Memory->new
    );
    $main->timeline('test');
    my $view = new_ok("BusyBird::Main::PSGI::View", [main_obj => $main]);

    test_psgi_response($view->response_notfound(), 400, "notfound");
    
    test_json_response($view->response_json(200, {}),
                       200, {error => undef}, "json, 200, empty hash");
    test_json_response($view->response_json(200, [0,1,2]),
                       200, [0,1,2], "json, 200, array");
    test_json_response($view->response_json(400, {}),
                       400, {}, "json, 400, empty hash");
    test_json_response($view->response_json(500, {error => "something bad happened"}),
                       500, {error => "something bad happened"}, "json, 500, error set");
    test_json_response($view->response_json(200, {main => $main}),
                       500, {error => "error while encoding to JSON"}, "json, 500, unable to encode");

    test_psgi_response($view->response_statuses(statuses => [], http_code => 200, format => "html", timeline_name => "test"),
                       200, "statuses success");
    test_psgi_response($view->response_statuses(error => "hoge", http_code => 400, format => "html", timelien_name => "test"),
                       400, "statuses failure");

    test_psgi_response($view->response_timeline("test"), 200, "existent timeline");
    test_psgi_response($view->response_timeline("hoge"), 404, "missing timeline");
}


done_testing();

