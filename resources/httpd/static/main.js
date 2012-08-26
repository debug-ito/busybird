//// BusyBird main script
//// Copyright (c) 2012 Toshio ITO

function bbUserCommand(params) {
    this.lock_counter = (params.init_lock || 0);
    this.keys = [];
    this.onLocked = (params.onLocked || function(){});
    this.onUnlocked = (params.onUnlocked || function(){});
    this.onTriggered = (params.onTriggered || function(){});
}
bbUserCommand.prototype = {
    lock: function() {
        return this.setLock(this.lock_counter + 1);
    },
    unlock: function() {
        return this.setLock(this.lock_counter - 1);
    },
    setLock: function(new_count) {
        var old_count = this.lock_counter;
        if(new_count < 0) new_count = 0;
        this.lock_counter = new_count;
        if(new_count <= 0 && old_count > 0) {
            this.onUnlocked();
        }else if(new_count > 0 && old_count <= 0) {
            this.onLocked();
        }
        return this;
    },
    trigger: function() {
        if(this.lock_counter <= 0) {
            this.onTriggered();
        }
    },
    addKey: function(keys) {
        this.keys.push(keys);
        return this;
    }
};

function bbIndicator($show_target) {
    this.$show_target = $show_target;
}
bbIndicator.prototype = {
    show: function(msg, type, timeout) {
        var self = this;
        this.$show_target.text(msg).show();
        if(timeout != null && timeout > 0) {
            setTimeout(function() {
                self.$show_target.fadeOut('fast');
            }, timeout);
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
            for(var i = 0 ; i < self.status_listeners.length ; i++) {
                var name   = "sidebar-item-" + self.status_listeners[i].getName();
                var header = self.status_listeners[i].getHeader();
                var detail = self.status_listeners[i].getDetail();
                if(header == null) continue;
                sidebar_text += '<div class="accordion-group"><div class="accordion-heading">';
                if(detail == null) {
                    sidebar_text += '<span class="accordion-toggle">' + header + "</span></div></div>\n";
                }else {
                    sidebar_text += '<a class="accordion-toggle" data-toggle="collapse" data-parent="#sidebar" href="#'+name+'">'+header+"</a></div>\n";
                    sidebar_text += '<div class="accordion-body collapse" id="'+name+'"><div class="accordion-inner sidebar-detail">'+"\n";
                    sidebar_text += detail + "\n</div></div></div>\n";
                }
            }
            $('#sidebar').html(sidebar_text);
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
    indicator: null,

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
            console.log("ajaxRetry: canceller called");
            if(ajax_xhr != null) {
                console.log("ajaxRetry: xhr aborted.");
                ajax_xhr.abort();
            }
        };
        return deferred;
    },
    
    linkify: function (text, entities) {
        var found_in_entities = {};
        if(entities && entities.urls) {
            for(var i = 0 ; i < entities.urls.length ; i++) {
                var url_entry = entities.urls[i];
                found_in_entities[url_entry.url] = url_entry;
            }
        }
        return text.replace(/https?:\/\/[\x21-\x7E]+/g, function(orig_url) {
            var text = orig_url;
            if(orig_url in found_in_entities) {
                text = found_in_entities[orig_url].expanded_url;
            }
            return '<a href="'+ orig_url +'">'+ text +'</a>';
        });
    },

    formatStatus: function (status, show_by_default) {
        var img_tag = "";
        var level = status.busybird.level;
        if(!level) level = 0;
        var style_display = (show_by_default ? "" : 'style="display: none"');
        var timestamp_str = status.created_at;
        if(status.busybird.status_permalink != null) {
            timestamp_str = '<a href="'+status.busybird.status_permalink+'">'+timestamp_str+'</a>';
        }
        var ret = '<li class="status-container" '+ style_display +' busybird-level="'+ level +'" onclick="bb.setCursor($(this));">';
        if(status.user.profile_image_url) {
            img_tag = '<img class="status-profile-image" src="'+ status.user.profile_image_url +'" width="48" height="48" />';
        }
        ret += '<div class="status-profile-image">'+ img_tag +'</div>';
        ret += '<div class="status-main">'
        ret +=   '<div class="status-header">';
        ret +=     '<div class="status-attributes">';
        ret +=       (status.busybird.is_new ? '<span class="label label-success bb-status-is-new">NEW</span>&nbsp;' : '');
        ret +=       '<span class="label">Lv.'+ level + '</span>';
        ret +=     '</div>';
        ret +=     '<div class="status-user-name">';
        ret +=       '<strong>' + status.user.screen_name + '</strong>&nbsp;&nbsp;';
        ret +=       '<span class="status-created-at">'+ timestamp_str + '</span>';
        ret +=     '</div>';
        ret +=   '</div>'
        ret +=   '<div class="status-text">'+ this.linkify(status.text, status.entities) + '</div>';
        ret += '</div>'
        ret += "</li>\n";
        return ret;
    },

    formatHiddenStatus: function (invisible_num) {
        return '<li class="hidden-status-header">'+ invisible_num +' statuses hidden here.</li>';
    },

    blockRepeat: function(orig_array, block_size, each_func) {
        var block_num = Math.ceil(orig_array.length / block_size);
        return Deferred.repeat(block_num, function(block_index) {
            var start_global_index = block_size * block_index;
            // console.log("blockRepeat: block_size: " + block_size + ", block_index: " + block_index);
            each_func(orig_array.slice(start_global_index, start_global_index + block_size), start_global_index);
        });
    },

    renderStatuses: function(statuses, is_prepend) {
        // console.log("renderStatuses: start");
        var $statuses = $("#statuses");
        if(statuses.length <= 0) return;
        var total_index = 0;
        if(is_prepend) {
            $statuses.find(".bb-status-is-new").remove();
            statuses = statuses.reverse();
        }
        var new_entries = [];
        return bb.blockRepeat(statuses, 100, function(block_array) {
            var statuses_text = "";
            for(var i = 0 ; i < block_array.length ; i++) {
                var status = block_array[i];
                if(status.id == bb.more_status_max_id) continue;
                var this_status_text = bb.formatStatus(status);
                if(is_prepend) {
                    statuses_text =  this_status_text + statuses_text;
                }else {
                    statuses_text = statuses_text + this_status_text;
                }
            }
            if(is_prepend) {
                // $statuses.prepend(statuses_text);
                new_entries.unshift.apply(new_entries, $(statuses_text).prependTo($statuses).get()); //** use apply() to expand array argument
            }else {
                // $statuses.append(statuses_text);
                new_entries.push.apply(new_entries, $(statuses_text).appendTo($statuses).get());
            }
        }).next(function() {
            // console.log("renderStatuses: repeat finished.");
            if(!is_prepend) {
                bb.more_status_max_id = statuses[statuses.length-1].id;
            }
            console.log("new entries num: " + new_entries.length);
            return bb.changeDisplayLevel(0, true, true, true, $(new_entries));
        });
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

    distanceRanges: function (a_top, a_range, b_top, b_range) {
        var a_btm = a_top + a_range;
        var b_btm = b_top + b_range;
        var dist_top = a_top  - b_top
        var dist_btm = b_btm - a_btm;
        var signed_dist = (dist_top > dist_btm ? dist_top : dist_btm);
        return (signed_dist > 0 ? signed_dist : 0);
    },

    distanceToWindow: function ($elem) {
        return bb.distanceRanges($(window).scrollTop(), $(window).height(),
                                 $elem.offset().top, $elem.height());
    },

    getTime: function () {
        return (new Date()).getTime();
    },

    changeDisplayLevel: function(change_level, is_relative, no_animation, no_window_adjust, $status_and_header_set) {
        var start_time = bb.getTime();
        var end_time;
        var show_time = function(msg) {
            end_time = bb.getTime();
            console.log("changeDisplayLevel: " + msg + " (" + (end_time - start_time) + " ms)");
            start_time = end_time;
        };
        show_time("start");
        
        if(change_level != null) {
            if(is_relative) {
                bb.display_level += change_level;
            }else {
                bb.display_level = change_level;
            }
        }
        var current_display_level = bb.display_level;
        
        $('.display-level').text(bb.display_level);
        $('.bbtest-anchor').removeClass('bbtest-anchor');

        // var $statuses_container = $('#statuses');
        if($status_and_header_set == null) {
            $status_and_header_set = $('#statuses').children();
        }
        var $status_entries = $status_and_header_set.filter('.status-container');
        if($status_entries.length <= 0) return;

        var ACTION_STAY_VISIBLE = 0;
        var ACTION_STAY_INVISIBLE = 1;
        var ACTION_GET_VISIBLE = 2;
        var ACTION_GET_INVISIBLE = 3;
        var ANIMATION_MAX = 15;

        var metrics_list = [];
        var hidden_header_list = [];
        var win_dim = {"top": $(window).scrollTop(), "range": $(window).height()};
        var cursor_index = (bb.$cursor == null ? -1 : $status_entries.index(bb.$cursor));
        var cur_index = 0;
        var next_seq_invisible_entries = [];
        var prev_pos = 0;
        var window_adjuster = function() {};
        return bb.blockRepeat($status_entries.get(), 150, function(status_block) { $.each(status_block, function(index_in_block, cur_entry) {
            var $cur_entry = $(cur_entry);
            var entry_level = $cur_entry.attr('busybird-level');
            var cur_is_visible = ($cur_entry.css('display') != 'none');
            var metric = {};
            metric.$status_entry = $cur_entry;
            if(entry_level <= current_display_level) {
                metric.action = (cur_is_visible ? ACTION_STAY_VISIBLE : ACTION_GET_VISIBLE);
                if(next_seq_invisible_entries.length > 0) {
                    hidden_header_list.push({'$followed_by': $cur_entry, 'entries': next_seq_invisible_entries});
                    next_seq_invisible_entries = [];
                }
            }else {
                metric.action = (cur_is_visible ? ACTION_GET_INVISIBLE : ACTION_STAY_INVISIBLE);
                next_seq_invisible_entries.push($cur_entry);
            }
            var cur_pos = (cur_is_visible ? $cur_entry.offset().top : prev_pos);
            metric.win_dist = bb.distanceRanges(win_dim.top, win_dim.range, cur_pos, $cur_entry.height());
            metric.cursor_index_dist = Math.abs(cur_index - cursor_index);
            metrics_list.push(metric);
            prev_pos = cur_pos;
            cur_index++;
        })}).next(function () {
            if(next_seq_invisible_entries.length > 0) {
                hidden_header_list.push({'$followed_by': null, 'entries': next_seq_invisible_entries});
            }
            metrics_list = metrics_list.sort(function (a, b) {
                if(a.win_dist != b.win_dist) {
                    return a.win_dist - b.win_dist;
                }
                return a.cursor_index_dist - b.cursor_index_dist;
            });

            // $('.test-metrics-index').remove();
            // for(var i = 0 ; i < metrics_list.length ; i++) {
            //     metrics_list[i].$status_entry.find('.status-attributes').append('<span class="test-metrics-index">&nbsp; METRIC: '+i+'</span>');
            //     metrics_list[i].$status_entry.attr('busybird-metric', i);
            // }
            
            if(!no_window_adjust) {
                for(var i = 0 ; i < metrics_list.length ; i++) {
                    if(metrics_list[i].action == ACTION_STAY_VISIBLE) {
                        var $anchor_elem = metrics_list[i].$status_entry;
                        $anchor_elem.addClass('bbtest-anchor');
                        var relative_position_of_anchor = $anchor_elem.offset().top - $(window).scrollTop();
                        window_adjuster = function() {
                            $(window).scrollTop($anchor_elem.offset().top - relative_position_of_anchor);
                        };
                        break;
                    }
                }
            }
            
            var slide_options = {
                duration: bb.LEVEL_ANIMATION_DURATION,
                step: function(now, fx) {
                    if(fx.prop != "height") return;
                    window_adjuster();
                }
            };
            var action_list = $.map($.grep(metrics_list, function(elem) {
                return (elem.action == ACTION_GET_VISIBLE || elem.action == ACTION_GET_INVISIBLE);
            }), function(elem) {
                return elem.$status_entry.get();
            });
            var action_anim_list;
            var action_noanim_list;
            if(no_animation) {
                action_anim_list = [];
                action_noanim_list = action_list;
            }else {
                action_anim_list = action_list.slice(0, ANIMATION_MAX);
                action_noanim_list = action_list.slice(ANIMATION_MAX);
            }
            bb.detailedSlide($(action_anim_list), "toggle", slide_options);

            // $statuses_container.children(".hidden-status-header").remove();
            $status_and_header_set.filter(".hidden-status-header").remove();
            window_adjuster();
            return bb.blockRepeat(hidden_header_list, 40, function(header_block) {
                for(var i = 0 ; i < header_block.length ; i++) {
                    var header_entry = header_block[i];
                    if(header_entry.$followed_by != null) {
                        header_entry.$followed_by.before(bb.formatHiddenStatus(header_entry.entries.length));
                    }else {
                        // $statuses_container.append(bb.formatHiddenStatus(header_entry.entries.length));
                        $status_and_header_set.last().after(bb.formatHiddenStatus(header_entry.entries.length));
                    }
                }
                window_adjuster();
            }).next(function () {
                return bb.blockRepeat(action_noanim_list, 100, function(status_block) {
                    $(status_block).toggle();
                    window_adjuster();
                });
            });
        });
    }
};

function createDisplayLevelChanger(change_amount, target_button_id) {
    return new bbUserCommand({
        onTriggered: function () {
            bbcom.incriment_display_level.lock();
            bbcom.decriment_display_level.lock();
            bb.changeDisplayLevel(change_amount, true).next(function () {
                bbcom.incriment_display_level.unlock();
                bbcom.decriment_display_level.unlock();
            });
        },
        onLocked: function() {
            $(target_button_id).addClass("disabled");
        },
        onUnlocked: function() {
            $(target_button_id).removeClass("disabled");
        }
    });
}

var bbcom = {
    load_new_statuses: new bbUserCommand({
        init_lock: 1,
        onTriggered: function() {
            var self = this;
            bb.loadStatuses("new_statuses.json", true).next(function(){
                // self.unlock();
                return bb.confirm();
            });
            self.lock();
        },
        onLocked: function() {
            $(".bb-new-status-loader-button").addClass("disabled").removeAttr("href");
        },
        onUnlocked: function() {
            $('.bb-new-status-loader-button')
                .removeClass("disabled")
                .prop('href', 'javascript: bbcom.load_new_statuses.trigger();');
        }
    }),

    load_more_statuses: new bbUserCommand({
        onTriggered: function() {
            // var $more_button_selec = $("#more-button").removeAttr("href").button('loading');
            var self = this;
            self.lock();
            bb.loadStatusesWithMaxID(null).next(function() {
                self.unlock();
                // $more_button_selec.attr("href", 'javascript: bbui.loadMoreStatuses();').button('reset');
            });
        },
        onLocked: function() {
            $("#more-button").removeAttr("href").button('loading');
        },
        onUnlocked: function() {
            $("#more-button").attr("href", 'javascript: bbcom.load_more_statuses.trigger();').button('reset');
        }
    }),

    incriment_display_level: createDisplayLevelChanger(+1, "#bb-button-incriment-display-level"),
    decriment_display_level: createDisplayLevelChanger(-1, "#bb-button-decriment-display-level"),

    toggle_run_mode: new bbUserCommand({
        onTriggered: function() {
            poller.toggleSelection("new_statuses");
            $('#bb-button-stop-mode').toggleClass("active");
            $('#bb-button-run-mode').toggleClass("active");
        }
    }),
};

// var bbui = {
//     loadNewStatuses: function () {
//         bb.loadStatuses("new_statuses.json", true).next(function(){
//             return bb.confirm();
//         });
//         $(".bb-new-status-loader-button").addClass("disabled").removeAttr("href");
//     },
//     loadMoreStatuses: function () {
//         var $more_button_selec = $("#more-button").removeAttr("href").button('loading');
//         bb.loadStatusesWithMaxID(null).next(function() {
//             $more_button_selec.attr("href", 'javascript: bbui.loadMoreStatuses();').button('reset');
//         });
//     },
//     incrimentDisplayLevel: function() {
//         bb.changeDisplayLevel(+1, true);
//     },
//     decrimentDisplayLevel: function() {
//         bb.changeDisplayLevel(-1, true);
//     },
//     toggleRunMode: function() {
//         poller.toggleSelection("new_statuses");
//         $('#bb-button-stop-mode').toggleClass("active");
//         $('#bb-button-run-mode').toggleClass("active");
//     }
// };

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

function bbSelectionPoller(url_base) {
    this.url_base = url_base;
    this.cur_deferred = null;
    this.elems = {};
}
bbSelectionPoller.prototype = {
    isRunning: function () {
        return (this.cur_deferred != null);
    },
    
    execute: function () {
        var req_params = [];
        var self = this;
        if(self.isRunning()) {
            console.log("poller: cancel deferred.");
            self.cur_deferred.cancel();
        }
        for(var elemkey in self.elems) {
            if(!self.elems[elemkey].isEnabled()) continue;
            req_params.push(elemkey + "=" + self.elems[elemkey].getRequestBase());
        }
        var req_url = self.url_base;
        if(req_params.length > 0) {
            req_url += "?" + req_params.join("&");
        }
        self.cur_deferred = bb.ajaxRetry({url: req_url, type: "GET", cache: false, dataType: "json", timeout: 0});
        self.cur_deferred.next(function (data, textStatus, jqXHR) {
            var defers = [];
            for(var key in data) {
                if(key in self.elems && data[key] != null) {
                    var d = self.elems[key].consumeResource(data[key]);
                    if(d != null) defers.push(d);
                }
            }
            return Deferred.parallel(defers);
        }).next(function () {
            self.cur_deferred = null;
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
    },
    changeSelection: function (changes) {
        var changed = false;
        for(var name in changes) {
            var to_state = changes[name];
            if(this.elems[name].isEnabled() != to_state) {
                this.elems[name].setEnabled(to_state);
                changed = true;
            }
        }
        if(changed && this.isRunning()) {
            this.execute();
        }
    },
    toggleSelection: function (names) {
        if(names == null) return;
        if(!(names instanceof Array)) {
            names = [names];
        }
        var changes = {};
        for(var i = 0 ; i < names.length ; i++) {
            var name = names[i];
            changes[name] = (this.elems[name].isEnabled() ? false : true);
        }
        this.changeSelection(changes);
    },
    selectionEnabled: function(name) {
        return (this.elems[name] == null ? false : this.elems[name].isEnabled());
    }
};

// ** For test
// bb.status_hook.addListener("wait", function(statuses, is_prepend) {
//     console.log("before wait");
//     return Deferred.wait(5).next(function() { console.log("after wait"); });
// });

bb.status_hook.addListener("renderer", function(statuses, is_prepend) {
    return bb.renderStatuses(statuses, is_prepend);
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


var poller = new bbSelectionPoller("state.json");
poller.add('new_statuses', 0, function(resource) {
    return bb.status_hook.runHook(resource, true).next(function() {
        return bb.confirm();
    });
});
poller.add('new_statuses_num', 0, function(resource) {
    this.setRequestBase(resource);
    document.title = (resource > 0 ? '('+ resource +') ' : "") + document.title.replace(/^\([0-9]*\) */, "");
    $('.bb-new-status-num').text(resource);
    if(resource > 0 && !poller.selectionEnabled('new_statuses')) {
        // $('.bb-new-status-loader-button').removeClass("disabled");
        bbcom.load_new_statuses.setLock(0);
    }else {
        bbcom.load_new_statuses.setLock(1);
    }
    // else {
    //     $('.bb-new-status-loader-button').addClass("disabled");
    // }
    // if(resource > 0) {
    //     bbcom.load_new_statuses.unlock();
    // }else {
    //     bbcom.load_new_statuses.lock();
    //     // $('.bb-new-status-loader-button')
    //     //     .addClass('disabled')
    //     //     .prop('href', "#");
    // }
});
poller.changeSelection({'new_statuses': false});

$(document).ready(function () {
    bb.indicator = new bbIndicator($('#bb-indicator'));
    bb.loadStatuses('all_statuses.json', false).next(function() {
        bb.setCursor($('#statuses > .status-container').first());
        bb.indicator.show("Initialized", null, 3000);
        return bb.confirm();
    }).next(function () {
        poller.execute();
    }).error(function(e) {
        console.log("ERROR!!! " + e);
    });
});

