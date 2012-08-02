//// BusyBird main script
//// Copyright (c) 2012 Toshio ITO

var bb = {
    AJAXRETRY_BACKOFF_INIT_MS : 500,
    AJAXRETRY_BACKOFF_FACTOR  : 2,
    AJAXRETRY_BACKOFF_MAX_MS  : 120000,

    status_listeners : [],
    
    ajaxRetry : function(ajax_param) {
        var ajax_xhr = null;
        var ajax_retry_ok = true;
        var ajax_retry_backoff = bb.AJAXRETRY_BACKOFF_INIT_MS;
        var deferred = new Deferred();
        ajax_param.success = function(data, textStatus, jqXHR) {
            deferred.call(data, textStatus, jqXHR);
        };
        ajax_param.error = function(jqXHR, textStatus, errorThrown) {
            ajax_xhr = null;
            ajax_retry_backoff *= bb.AJAXRETRY_BACKOFF_FACTOR;
            if(ajax_retry_backoff > bb.AJAXRETRY_BACKOFF_MAX_MS) {
                ajax_retry_backoff = bb.AJAXRETRY_BACKOFF_MAX_MS;
            }
            setTimeout(function() {
                if(ajax_retry_ok) ajax_xhr =  $.ajax(ajax_param);
            }, ajax_retry_backoff);
        };
        ajax_xhr = $.ajax(ajax_param);
        deferred.canceller = function () {
            ajax_retry_ok = false;
            if(ajax_xhr != null) ajax_xhr.abort()
        };
        return deferred;
    },
    
    linkify: function (text) {
        return text.replace(/(https?:\/\/[^ \r\n\t　]+)/g, "<a href=\"$1\">$1</a>");
    },

    formatStatus: function (status) {
        var ret = '<li>';
        var img_tag = "";
        if(status.user.profile_image_url) {
            img_tag = '<img class="status_profile_image" src="'+ status.user.profile_image_url +'" width="48" height="48" />';
        }
        ret += '<div class="status_profile_image">'+ img_tag +'</div>';
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

    renderStatuses: function(statuses, is_prepend) {
        var statuses_text = "";
        for(var i = 0 ; i < statuses.length ; i++) {
            statuses_text += bb.formatStatus(statuses[i]);
        }
        if(statuses.length > 0) {
            if(is_prepend) {
                $("#statuses").prepend(statuses_text);
            }else {
                $("#statuses").append(statuses_text);
                $("#more_button").attr("href", 'javascript: bbui.loadMoreStatuses("' + statuses[statuses.length-1].id + '")');
            }
        }
    },

    loadStatuses: function (req_point, is_prepend) {
        return bb.ajaxRetry({
            url: req_point,
            type: "GET",
            cache: false,
            dataType: "json",
            timeout: 0
        }).next(function (data, textStatus, jqXHR) {
            var defers = [];
            for(var i = 0 ; i < bb.status_listeners.length ; i++) {
                var d = bb.status_listeners[i].consumeStatuses(data, is_prepend);
                if(d != null) defers.push(d);
            }
            return Deferred.parallel(defers);
        });
    },

    confirm: function() {
        return bb.ajaxRetry({
            url: "confirm.json",
            type: "GET",
            cache: false,
            dataType: "text",
            timeout: 0
        });
    },

    addStatusListener: function(name, listen_callback) {
        bb.status_listeners.push(new bbStatusListener(name, listen_callback));
    },
};

var bbui = {
    loadNewStatuses: function () {
        bb.loadStatuses("new_statuses.json", true).next(function(){
            return bb.confirm();
        });
        $(".bb-new-status-loader-button").addClass("disabled").removeAttr("href");
    },
    loadMoreStatuses: function (max_id) {
        var more_button_selec = $("#more_button").removeAttr("href").button('loading');
        bb.loadStatuses("all_statuses?max_id=" + max_id, false).next(function () {
            more_button_selec.button('reset');
        });
    },
};

function bbSelectionElement(name, init_base, resource_callback) {
    this.name = name;
    this.request_base = init_base;
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

    setRequestBase: function(base) {
        this.request_base = base;
    },

    setEnabled: function (val) {
        this.is_enabled = val;
    },

    isEnabled: function() {
        return this.is_enabled;
    },
};

function bbSelectionPoller() {
    this.cur_deferred = null;
    this.elems = {};
}
bbSelectionPoller.prototype = {
    URL_BASE: "state.json",

    isRunning: function () {
        return (this.cur_deferred != null);
    },
    
    execute: function () {
        var req_params = [];
        var self = this;
        if(self.isRunning()) {
            self.cur_deferred.cancel();
        }
        for(var elemkey in self.elems) {
            if(!self.elems[elemkey].isEnabled()) continue;
            req_params.push(elemkey + "=" + self.elems[elemkey].getRequestBase());
        }
        var req_url = self.URL_BASE;
        if(req_params.length > 0) {
            req_url += "?" + req_params.join("&");
        }
        self.cur_deferred = 
            bb.ajaxRetry({url: req_url, type: "GET", cache: false, dataType: "json", timeout: 0})
            .next(function (data, textStatus, jqXHR) {
                var defers = [];
                for(var key in data) {
                    if(key in self.elems) {
                        var d = self.elems[key].consumeResource(data[key]);
                        if(d != null) defers.push(d);
                    }
                }
                return Deferred.parallel(defers);
            }).next(function () {
                self.execute();
            });
    },
    add: function (name, init_base, resource_callback) {
        this.addElem(new bbSelectionElement(name, init_base, resource_callback));
    },
    addElem: function (elem) {
        this.elems[elem.getName()] = elem;
        if(this.isRunning()) {
            this.execute();
        }
    }
};

function bbStatusListener(name, listener_callback) {
    this.name = name;
    this.header = null;
    this.detail = null;
    this.listener_callback = listener_callback;
}
bbStatusListener.prototype = {
    consumeStatuses: function(statuses, is_prepend) {
        return this.listener_callback(statuses, is_prepend);
    },
    getName: function () {
        return this.name;
    },
    getHeader: function() {
        return this.header;
    },
    getDetail: function() {
        return this.detail;
    },
};

// ** For test
// bb.addStatusListener("wait", function(statuses, is_prepend) {
//     console.log("before wait");
//     return Deferred.wait(5).next(function() { console.log("after wait"); });
// });

bb.addStatusListener("renderer", function(statuses, is_prepend) {
    console.log("renderer executed");
    bb.renderStatuses(statuses, is_prepend);
});


var poller = new bbSelectionPoller();
// poller.add('new_statuses', 0, function(resource) {
//     bb.renderStatuses(resource, true);
//     return bb.confirm();
// });
poller.add('new_statuses_num', 0, function(resource) {
    this.setRequestBase(resource);
    $('.bb-new-status-num').text(resource);
    if(resource > 0) {
        $('.bb-new-status-loader-button')
            .removeClass('disabled')
            .prop('href', 'javascript: bbui.loadNewStatuses()');
    }else {
        $('.bb-new-status-loader-button')
            .addClass('disabled')
            .prop('href', "#");
    }
});

$(document).ready(function () {
    bb.loadStatuses('all_statuses.json', false).next(function() {
        return bb.confirm();
    }).next(function () {
        poller.execute();
    });
});

