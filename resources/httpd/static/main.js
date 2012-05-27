
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
                bbCometLoadStatuses('new_statuses', true, true);
            }});
}

function bbLinkify(text) {
    return text.replace(/(https?:\/\/[^ \r\n\t　]+)/g, "<a href=\"$1\">$1</a>");
}

function bbFormatStatus(status) {
    var ret = "<li>";
    ret += '<div class="status_profile_image"><img class="status_profile_image" src="'+ status.user.profile_image_url +'" width="48" height="48" /></div>';
    ret += '<div class="status_main">'
    ret += '  <div class="status_header">';
    ret += '    <span class="status_user_name">' + status.user.screen_name + '</span>';
    ret += '    <span class="status_created_at"> at '+ status.created_at + '</span>';
    ret += '    <span>&nbsp;' + (status.busybird.is_new ? 'NEW' : 'OLD') + '</span>';
    ret += '  </div>'
    ret += '  <div class="status_text">'+ bbLinkify(status.text) + '</div>';
    ret += '</div>'
    ret += "</li>\n";
    return ret;
}

function bbCometLoadStatuses (req_point, is_prepend, need_confirm) {
    $.ajax({url: "/" + bbGetOutputName() + "/" + req_point,
            type: "GET",
            cache: false,
            dataType: "json",
            timeout: 0,
            error: function (jqXHR, textStatus, errorThrown) {
                setTimeout(function () {bbCometLoadStatuses(req_point, is_prepend);}, g_comet_error_interval_ms);
            },
            success: function (data, textStatus, jqXHR) {
                var i;
                var new_statuses_text = "";
                for(i = 0 ; i < data.length ; i++) {
                    new_statuses_text += bbFormatStatus(data[i]);
                }
                if(data.length > 0) {
                    if(is_prepend) {
                        $("#statuses").prepend(new_statuses_text);
                    }else {
                        $("#statuses").append(new_statuses_text);
                        $("#more_button").attr("onclick", 'bbCometLoadStatuses("all_statuses?max_id=' + data[data.length-1].id + '", false, false)');
                    }
                }
                if(need_confirm) bbCometConfirm();
            }});
}

$(document).ready(function () {
    bbCometLoadStatuses('all_statuses', false, true);
});

