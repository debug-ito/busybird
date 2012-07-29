
var bb = {
    AJAXRETRY_ERROR_INTERVAL_MS: 60000,
    ajaxRetry : function(ajax_param, callback) {
        var ajax_xhr = null;
        var ajax_retry_ok = true;
        ajax_param.success = callback;
        ajax_param.error = function(jqXHR, textStatus, errorThrown) {
            console.log("ajaxRetry: error: " + textStatus + ", errorThrown: " + errorThrown);
            ajax_xhr = null;
            setTimeout(function() {
                if(ajax_retry_ok) ajax_xhr =  $.ajax(ajax_param);
            }, bb.AJAXRETRY_ERROR_INTERVAL_MS);
        };
        ajax_xhr = $.ajax(ajax_param);
        return function () {
            ajax_retry_ok = false;
            if(ajax_xhr != null) ajax_xhr.abort()
        };
    },
    
    linkify: function (text) {
        return text.replace(/(https?:\/\/[^ \r\n\t　]+)/g, "<a href=\"$1\">$1</a>");
    },

    formatStatus: function (status) {
        var ret = '<li>';
        ret += '<div class="status_profile_image"><img class="status_profile_image" src="'+ status.user.profile_image_url +'" width="48" height="48" /></div>';
        ret += '<div class="status_main">'
        ret += '  <div class="status_header">';
        ret += '    <span class="status_user_name">' + status.user.screen_name + '</span>';
        ret += '    <span class="status_created_at"> at '+ status.created_at + '</span>';
        ret += '    <span>&nbsp;' + (status.busybird.is_new ? 'NEW' : 'OLD') + '</span>';
        ret += '  </div>'
        ret += '  <div class="status_text">'+ this.linkify(status.text) + '</div>';
        ret += '</div>'
        ret += "</li>\n";
        return ret;
    },

};

function bbSelectionElement(name, resource_callback) {
    this.name = name;
    this.request_base = "_";
    this.resource_callback = resource_callback;
    this.is_enabled = true;
}
bbSelectionElement.prototype = {
    consumeResource: function (resource) {
        return this.resource_callback(resource);
    },

    getName: function () {
        return this.name;
    },

    getRequestBase: function () {
        return this.request_base;
    },

    setEnabled: function (val) {
        this.is_enabled = val;
    },

    isEnabled: function() {
        return this.is_enabled;
    },
};

function bbSelectionPoller() {
    this.cur_aborter = null;
    this.elems = {};
}
bbSelectionPoller.prototype = {
    URL_BASE: "state",

    isRunning: function () {
        return (this.cur_aborter != null);
    },
    
    execute: function () {
        var req_params = [];
        var self = this;
        if(self.isRunning()) {
            self.cur_aborter();
        }
        for(var elemkey in self.elems) {
            if(!self.elems[elemkey].isEnabled()) continue;
            req_params.push(elemkey + "=" + self.elems[elemkey].getRequestBase());
        }
        var req_url = self.URL_BASE;
        if(req_params.length > 0) {
            req_url += "?" + req_params.join("&");
        }
        self.cur_aborter = 
            bb.ajaxRetry({url: req_url, type: "GET", cache: false, dataType: "json", timeout: 0}, function(data, textStatus, jqXHR) {
                for(var key in data) {
                    if(key in self.elems) {
                        self.elems[key].consumeResource(data[key]);
                        // ** TODO: collect deferred objects.
                    }
                }
                // ** TODO: call execute() after all colleted deferreds are done
                self.execute();
            });
    },
    add: function (elem) {
        this.elems[elem.getName()] = elem;
        if(this.isRunning()) {
            this.execute();
        }
    }
};

function bbCometConfirm() {
    bb.ajaxRetry({url: "confirm",
                  type: "GET",
                  cache: false,
                  dataType: "text",
                  timeout: 0},
                 function (data, textStatus, jqXHR) {
                     bbCometLoadStatuses('new_statuses', true, true);
                 });
}

function bbCometLoadStatuses (req_point, is_prepend, need_confirm) {
    bb.ajaxRetry({url: req_point,
                  type: "GET",
                  cache: false,
                  dataType: "json",
                  timeout: 0},
                 function (data, textStatus, jqXHR) {
                     var i;
                     var new_statuses_text = "";
                     for(i = 0 ; i < data.length ; i++) {
                         new_statuses_text += bb.formatStatus(data[i]);
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
                 });
}

$(document).ready(function () {
    bbCometLoadStatuses('all_statuses', false, true);
});

