//// BusyBird main script
//// Copyright (c) 2012 Toshio ITO

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

function bbStatusHook() {
    this.status_listeners = [];
}
bbStatusHook.prototype = {
    addListener: function(name, listener_callback) {
        this.status_listeners.push(new bbStatusListener(name, listener_callback));
    },
    runHook: function(statuses, is_prepend) {
        var defers = [];
        for(var i = 0 ; i < this.status_listeners.length ; i++) {
            var d = this.status_listeners[i].consumeStatuses(statuses, is_prepend);
            if(d != null) defers.push(d);
        }
        var self = this;
        return Deferred.parallel(defers).next(function() {
            var sidebar_text = "";
            console.log("start: runHook inner callback");
            console.log("  " + self.status_listeners.length + " listeners.");
            for(var i = 0 ; i < self.status_listeners.length ; i++) {
                var name   = "sidebar-item-" + self.status_listeners[i].getName();
                var header = self.status_listeners[i].getHeader();
                var detail = self.status_listeners[i].getDetail();
                console.log(i + "th hook: name: " + name);
                if(header == null) continue;
                console.log("  header: " + header);
                sidebar_text += '<div class="accordion-group"><div class="accordion-heading">';
                if(detail == null) {
                    sidebar_text += '<span class="accordion-toggle">' + header + "</span></div></div>\n";
                }else {
                    sidebar_text += '<a class="accordion-toggle" data-toggle="collapse" data-parent="#sidebar" href="#'+name+'">'+header+"</a></div>\n";
                    sidebar_text += '<div class="accordion-body collapse" id="'+name+'"><div class="accordion-inner sidebar-detail">'+"\n";
                    sidebar_text += detail + "\n</div></div></div>\n";
                }
            }
            console.log("before jquery: runHook inner callback");
            $('#sidebar').html(sidebar_text);
            console.log("end: runHook inner callback");
        });
    }
};

var bb = {
    AJAXRETRY_BACKOFF_INIT_MS : 500,
    AJAXRETRY_BACKOFF_FACTOR  : 2,
    AJAXRETRY_BACKOFF_MAX_MS  : 120000,
    LEVEL_ANIMATION_DURATION  : 400,

    status_hook: new bbStatusHook(),
    display_level: 0,
    $cursor: null,
    more_status_max_id: null,

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
        var img_tag = "";
        var level = status.busybird.level;
        if(!level) level = 0;
        var ret = '<li class="status-container" busybird-level="'+ level +'" onclick="bb.setCursor($(this));">';
        if(status.user.profile_image_url) {
            img_tag = '<img class="status-profile-image" src="'+ status.user.profile_image_url +'" width="48" height="48" />';
        }
        ret += '<div class="status-profile-image">'+ img_tag +'</div>';
        ret += '<div class="status-main">'
        ret +=   '<div class="status-header">';
        ret +=     '<div class="status-attributes">';
        ret +=       (status.busybird.is_new ? 'NEW' : 'OLD') + ', Lv.'+ level;
        ret +=     '</div>';
        ret +=     '<div class="status-user-name">';
        ret +=       '<strong>' + status.user.screen_name + '</strong>&nbsp;&nbsp;';
        ret +=       '<span class="status-created-at">'+ status.created_at + '</span>';
        ret +=     '</div>';
        ret +=   '</div>'
        ret +=   '<div class="status-text">'+ this.linkify(status.text) + '</div>';
        ret += '</div>'
        ret += "</li>\n";
        return ret;
    },

    formatHiddenStatus: function (invisible_num) {
        return '<li class="hidden-status-header">'+ invisible_num +' statuses hidden here.</li>';
    },

    renderStatuses: function(statuses, is_prepend) {
        var statuses_text = "";
        for(var i = 0 ; i < statuses.length ; i++) {
            if(statuses[i].id == bb.more_status_max_id) {
                continue;
            }
            statuses_text += bb.formatStatus(statuses[i]);
        }
        if(statuses.length > 0) {
            if(is_prepend) {
                $("#statuses").prepend(statuses_text);
            }else {
                $("#statuses").append(statuses_text);
                // $("#more-button").attr("href", 'javascript: bbui.loadMoreStatuses("' + statuses[statuses.length-1].id + '")');
                bb.more_status_max_id = statuses[statuses.length-1].id;
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
            return bb.status_hook.runHook(data, is_prepend);
        });
    },

    loadStatusesWithMaxID: function(max_id) {
        if(max_id == null) max_id = bb.more_status_max_id;
        if(max_id == null) {
            console.log("ERROR: bb.loadWithMaxID: max_id is null.");
            return Deferred.next();
        }
        return bb.loadStatuses("all_statuses?max_id=" + max_id, false);
    },

    confirm: function() {
        // console.log("start: confirm");
        return bb.ajaxRetry({
            url: "confirm.json",
            type: "GET",
            cache: false,
            dataType: "text",
            timeout: 0
        });
            // .next(function() {
            //     console.log("end: confirm");
            // });
    },

    setCursor: function ($cur_obj) {
        if(bb.$cursor != null) {
            bb.$cursor.removeClass("bb-cursor");
        }
        bb.$cursor = $cur_obj;
        if(bb.$cursor != null) {
            bb.$cursor.addClass("bb-cursor");
        }
    },

    detailedSlide: function($selection, target, options) {
        $selection.animate(
            { "height": target,
              "marginTop": target,
              "marginBottom": target,
              "paddingTop": target,
              "paddingBottom": target
            },
            options
        );
    },

    distanceElems: function ($elem_a, $elem_b) {
        if($elem_a == null || $elem_b == null) return 0;
        return Math.abs($elem_a.offset().top - $elem_b.offset().top);
    },

    distanceToWindow: function ($elem) {
        var win_top = $(window).scrollTop();
        var win_btm = win_top + $(window).height();
        var elem_top = $elem.offset().top;
        var elem_btm = elem_top + $elem.height();
        var dist_top = win_top  - elem_top
        var dist_btm = elem_btm - win_btm;
        var signed_dist = (dist_top > dist_btm ? dist_top : dist_btm);
        return (signed_dist > 0 ? signed_dist : 0);
    },

    changeDisplayLevel: function(change_level, is_relative) {
        var old_level = bb.display_level;
        if(change_level != null) {
            if(is_relative) {
                bb.display_level += change_level;
            }else {
                bb.display_level = change_level;
            }
        }
        $('.display-level').text(bb.display_level);

        $('.bbtest-anchor').removeClass('bbtest-anchor');
        
        var stayvisible_level = (bb.display_level > old_level ? old_level : bb.display_level);
        var $anchor_elem = null;
        var min_dist_win = 0;
        var min_dist_cursor = 0;
        
        var invisible_num = 0;
        var $statuses_container = $('#statuses');
        var $visibles = $();
        var $invisibles = $();
        var inserts = [];
        $statuses_container.children(".status-container").each(function(index, elem) {
            var entry_level = $(this).attr('busybird-level');
            if(entry_level <= stayvisible_level) {
                // ** search for anchor element
                var this_dist_win = bb.distanceToWindow($(this));
                var this_dist_cursor = bb.distanceElems(bb.$cursor, $(this));
                if(($anchor_elem == null)
                   || (this_dist_win < min_dist_win)
                   || (this_dist_win == min_dist_win && this_dist_cursor < min_dist_cursor)) {
                    $anchor_elem = $(this);
                    min_dist_win = this_dist_win;
                    min_dist_cursor = this_dist_cursor;
                }
            }
            if(entry_level <= bb.display_level) {
                // ** Collect visible elements
                $visibles = $visibles.add($(this));
                if(invisible_num > 0) {
                    // $visibles = $visibles.add($(bb.formatHiddenStatus(invisible_num)).insertBefore($(this)));
                    // $(this).before(bb.formatHiddenStatus(invisible_num));
                    inserts.push({"$pos_elem": $(this), "num": invisible_num});
                    invisible_num = 0;
                }
            }else {
                // ** Collect invisible elements
                // $(this).css('display', 'none');
                $invisibles = $invisibles.add($(this));
                invisible_num++;
            }
            return true;
        });
        var window_adjuster = null;
        if($anchor_elem != null) {
            $anchor_elem.addClass('bbtest-anchor');
            var relative_position_of_anchor = $anchor_elem.offset().top - $(window).scrollTop();
            window_adjuster = function() {
                $(window).scrollTop($anchor_elem.offset().top - relative_position_of_anchor);
            };
        }
        $statuses_container.children(".hidden-status-header").remove();
        if(window_adjuster) window_adjuster();
        for(var i = 0 ; i < inserts.length ; i++) {
            inserts[i].$pos_elem.before(bb.formatHiddenStatus(inserts[i].num));
        }
        if(invisible_num > 0) {
            // $visibles = $visibles.add($(bb.formatHiddenStatus(invisible_num)).appendTo($statuses_container));
            $statuses_container.append(bb.formatHiddenStatus(invisible_num));
        }
        if(window_adjuster) window_adjuster();
        var options = {
            duration: bb.LEVEL_ANIMATION_DURATION,
            step: window_adjuster,
            complete: window_adjuster
        };
        bb.detailedSlide($visibles, "show", options);
        bb.detailedSlide($invisibles, "hide", options);
    }
};

var bbui = {
    loadNewStatuses: function () {
        bb.loadStatuses("new_statuses.json", true).next(function(){
            return bb.confirm();
        });
        $(".bb-new-status-loader-button").addClass("disabled").removeAttr("href");
    },
    loadMoreStatuses: function () {
        var $more_button_selec = $("#more-button").removeAttr("href").button('loading');
        bb.loadStatusesWithMaxID(null).next(function() {
            $more_button_selec.attr("href", 'javascript: bbui.loadMoreStatuses();').button('reset');
        });
    },
    incrimentDisplayLevel: function() {
        bb.changeDisplayLevel(+1, true);
    },
    decrimentDisplayLevel: function() {
        bb.changeDisplayLevel(-1, true);
    }
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

// ** For test
// bb.status_hook.addListener("wait", function(statuses, is_prepend) {
//     console.log("before wait");
//     return Deferred.wait(5).next(function() { console.log("after wait"); });
// });

bb.status_hook.addListener("renderer", function(statuses, is_prepend) {
    bb.renderStatuses(statuses, is_prepend);
});
bb.status_hook.addListener("num-of-new-statuses", function(statuses, is_prepend) {
    var num_of_new = 0;
    for(var i = 0 ; i < statuses.length ; i++) {
        if(statuses[i].busybird.is_new) num_of_new++;
    }
    if(num_of_new > 0) {
        this.header = '<span class="badge badge-info">'+ num_of_new + "</span> new status" + (num_of_new > 1 ? "es" : "") + ' loaded.';
    }
});
bb.status_hook.addListener("owner-of-new-statuses", function(statuses, is_prepend) {
    var owner_count = {};
    for(var i = 0 ; i < statuses.length ; i++) {
        if(!statuses[i].busybird.is_new) continue;
        var status = statuses[i];
        if(!(status.user.screen_name in owner_count)) {
            owner_count[status.user.screen_name] = {
                "name": status.user.screen_name,
                "image": status.user.profile_image_url,
                "count": 0
            };
        }
        owner_count[status.user.screen_name].count++;
    }
    var owner_array = [];
    // ** Is there no equivalent to Perl's values() function in Javascript???
    for(var key in owner_count) {
        owner_array.push(owner_count[key]);
    }
    if(owner_array.length == 0) {
        return;
    }
    owner_array.sort(function(a, b) {
        return b.count - a.count;
    });
    this.header = '<span class="badge badge-info">' + owner_array.length + '</span> people tweeted.';
    this.detail = "<ol>\n";
    for(var i = 0 ; i < owner_array.length ; i++) {
        this.detail += '<li>' + owner_array[i].name + ' : ' + owner_array[i].count + ' tweet'
            + (owner_array[i].count > 1 ? "s" : "") + "</li>\n";
    }
    this.detail += "</ol>\n";
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
        bb.setCursor($('#statuses > .status-container').first());
        return bb.confirm();
    }).next(function () {
        poller.execute();
    }).error(function(e) {
        console.log("ERROR!!! " + e);
    });
});

