
var g_comet_error_interval_ms = 60000;
// ** TODO:: Error handling
// ** Maybe we should count total number of errors and stop retrying at a certain point.
// ** Or maybe we should appy decaying interval (exponential increase or something...)
function bbCometConfirm() {
    $.ajax({url: "/" + bbGetOutputName() + "/confirm",
            type: "GET",
            cache: false,
            dataType: "text",
            timeout: 0,
            error: function (jqXHR, textStatus, errorThrown) {
                setTimeout(bbCometConfirm, g_comet_error_interval_ms);
            },
            success: function (data, textStatus, jqXHR) {
                bbCometNewStatuses();
            }});
}

function bbFormatStatus(status) {
    var ret = "<li>";
    ret += '<div class="status_profile_image"><img class="status_profile_image" src="'+ status.user.profile_image_url +'" width="48" height="48" /></div>';
    ret += '<div class="status_main">'
    ret += '  <div class="status_header">';
    ret += '    <span class="status_user_name">' + status.user.screen_name + '</span>';
    ret += '    <span class="status_created_at"> at '+ status.created_at + '</span>';
    ret += '  </div>'
    ret += '  <div class="status_text">'+ status.text + '</div>';
    ret += '</div>'
    ret += "</li>\n";
    return ret;
}

function bbCometNewStatuses () {
    $.ajax({url: "/" + bbGetOutputName() + "/new_statuses",
            type: "GET",
            cache: false,
            dataType: "json",
            timeout: 0,
            error: function (jqXHR, textStatus, errorThrown) {
                setTimeout(bbCometNewStatuses, g_comet_error_interval_ms);
            },
            success: function (data, textStatus, jqXHR) {
                var i;
                var new_statuses_text = "";
                for(i = 0 ; i < data.length ; i++) {
                    new_statuses_text += bbFormatStatus(data[i]);
                }
                $("#statuses").prepend(new_statuses_text);
                bbCometConfirm();
            }});
}
$(document).ready(bbCometNewStatuses);

