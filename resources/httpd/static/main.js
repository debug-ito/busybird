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
        ret +=       '<span class="status-created-at">'+ status.created_at + '</span>';
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
            console.log("blockRepeat: block_size: " + block_size + ", block_index: " + block_index);
            each_func(orig_array.slice(start_global_index, start_global_index + block_size), start_global_index);
        });
    },

    renderStatuses: function(statuses, is_prepend) {
        console.log("renderStatuses: start");
        var BLOCK_SIZE = 20;
        // var statuses_text = "";
        var $statuses = $("#statuses");
        if(statuses.length <= 0) return;
        var block_num = Math.ceil(statuses.length / BLOCK_SIZE);
        var total_index = 0;
        if(is_prepend) {
            $statuses.find(".bb-status-is-new").remove();
            statuses = statuses.reverse();
        }
        return bb.blockRepeat(statuses, BLOCK_SIZE, function(block_array) {
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
                $statuses.prepend(statuses_text);
            }else {
                $statuses.append(statuses_text);
            }
        }).next(function() {
            console.log("renderStatuses: repeat finished.");
            if(!is_prepend) {
                bb.more_status_max_id = statuses[statuses.length-1].id;
            }
            return bb.changeDisplayLevel(0, true, true, true)
        });

        ///
        // return Deferred.repeat(block_num, function(block_index) {
        //     console.log("renderStatuses: repeat " + block_index);
        //     var this_index = 0;
        //     var statuses_text = "";
        //     while(this_index < BLOCK_SIZE && total_index < statuses.length) {
        //         var status_index = (is_prepend ? statuses.length - 1 - total_index : total_index);
        //         if(statuses[status_index].id == bb.more_status_max_id) continue;
        //         var this_status_text = bb.formatStatus(statuses[status_index]);
        //         if(is_prepend) {
        //             statuses_text =  this_status_text + statuses_text;
        //         }else {
        //             statuses_text = statuses_text + this_status_text;
        //         }
        //         this_index++;
        //         total_index++;
        //     }
        //     if(is_prepend) {
        //         $statuses.prepend(statuses_text);
        //     }else {
        //         $statuses.append(statuses_text);
        //     }
        // }).next(function() {
        //     console.log("renderStatuses: repeat finished.");
        //     if(!is_prepend) {
        //         bb.more_status_max_id = statuses[statuses.length-1].id;
        //     }
        //     return bb.changeDisplayLevel(0, true, true, true)
        // });
        // for(var i = 0 ; i < statuses.length ; i++) {
        //     if(statuses[i].id == bb.more_status_max_id) {
        //         continue;
        //     }
        //     statuses_text += bb.formatStatus(statuses[i]);
        // }
        // if(statuses.length > 0) {
        //     if(is_prepend) {
        //         $statuses.find(".bb-status-is-new").remove();
        //         $statuses.prepend(statuses_text);
        //     }else {
        //         $statuses.append(statuses_text);
        //         // $("#more-button").attr("href", 'javascript: bbui.loadMoreStatuses("' + statuses[statuses.length-1].id + '")');
        //         bb.more_status_max_id = statuses[statuses.length-1].id;
        //     }
        // }
        // bb.changeDisplayLevel(0, true, true, true);
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
        // var win_top = $(window).scrollTop();
        // var win_btm = win_top + $(window).height();
        // var elem_top = $elem.offset().top;
        // var elem_btm = elem_top + $elem.height();
        // var dist_top = win_top  - elem_top
        // var dist_btm = elem_btm - win_btm;
        // var signed_dist = (dist_top > dist_btm ? dist_top : dist_btm);
        // return (signed_dist > 0 ? signed_dist : 0);
    },

    getTime: function () {
        return (new Date()).getTime();
    },

    changeDisplayLevel: function(change_level, is_relative, no_animation, no_window_adjust) {
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

        var $statuses_container = $('#statuses');
        var $status_entries = $statuses_container.children('.status-container');
        if($status_entries.length <= 0) return;

        var ACTION_STAY_VISIBLE = 0;
        var ACTION_STAY_INVISIBLE = 1;
        var ACTION_GET_VISIBLE = 2;
        var ACTION_GET_INVISIBLE = 3;
        var ANIMATION_MAX = 15;

        // var $cur_entry = $status_entries.first();
        var metrics_list = [];
        var hidden_header_list = [];
        var win_dim = {"top": $(window).scrollTop(), "range": $(window).height()};
        var cursor_pos = (bb.$cursor == null ? (win_dim.top + win_dim.range / 2.0) : bb.$cursor.offset().top);
        var next_seq_invisible_entries = [];
        var invisible_index = 0;
        var prev_pos = 0;
        var window_adjuster = function() {};
        return Deferred.repeat($status_entries.length, function(repeat_index) {
            var $cur_entry = $status_entries.slice(repeat_index, repeat_index + 1);
            var entry_level = $cur_entry.attr('busybird-level');
            var cur_is_visible = ($cur_entry.css('display') != 'none');
            if(cur_is_visible) {
                invisible_index = 0;
            }else {
                invisible_index++;
            }
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
            metric.cursor_signed_dist = cur_pos - cursor_pos;
            metric.invisible_index = invisible_index;
            metrics_list.push(metric);
            prev_pos = cur_pos;
        }).next(function () {
            if(next_seq_invisible_entries.length > 0) {
                hidden_header_list.push({'$followed_by': null, 'entries': next_seq_invisible_entries});
            }
            metrics_list = metrics_list.sort(function (a, b) {
                if(a.win_dist != b.win_dist) {
                    return a.win_dist - b.win_dist;
                }
                if(Math.abs(a.cursor_signed_dist) != Math.abs(b.cursor_signed_dist)) {
                    return Math.abs(a.cursor_signed_dist) - Math.abs(b.cursor_signed_dist);
                }
                if(a.cursor_signed_dist >= 0 && b.cursor_signed_dist >= 0) {
                    return a.invisible_index - b.invisible_index;
                }else if(a.cursor_signed_dist <= 0 && b.cursor_signed_dist <= 0) {
                    return b.invisible_index - a.invisible_index;
                }else {
                    // ** sgn(a.cursor_signed_dist) != sgn(b.cursor_signed_dist): I guess this is a very rare case.
                    return 0;
                }
            });

            $('.test-metrics-index').remove();
            for(var i = 0 ; i < metrics_list.length ; i++) {
                metrics_list[i].$status_entry.find('.status-attributes').append('<span class="test-metrics-index">&nbsp; METRIC: '+i+'</span>');
                metrics_list[i].$status_entry.attr('busybird-metric', i);
            }
            
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
            $statuses_container.children(".hidden-status-header").remove();
            window_adjuster();
            for(var i = 0 ; i < hidden_header_list.length ; i++) {
                var header_entry = hidden_header_list[i];
                if(header_entry.$followed_by != null) {
                    header_entry.$followed_by.before(bb.formatHiddenStatus(header_entry.entries.length));
                }else {
                    $statuses_container.append(bb.formatHiddenStatus(header_entry.entries.length));
                }
            }
            window_adjuster();
            // for(var i = ANIMATION_MAX ; i < metrics_list.length ; i++) {
            //     if(metrics_list[i].action == ACTION_GET_VISIBLE || metrics_list[i].action == ACTION_GET_INVISIBLE) {
            //         metrics_list[i].$status_entry.toggle();
            //         metrics_list[i].$status_entry.attr('busybird-action', 'no-anim');
            //     }else {
            //         metrics_list[i].$status_entry.attr('busybird-action', 'none,no-anim');
            //     }
            // }
            // window_adjuster();


            for(var i = 0 ; i < metrics_list.length ; i++) {
                metrics_list[i].$status_entry.attr('busybird-action', '');
            }
            
            var slide_options = {
                duration: bb.LEVEL_ANIMATION_DURATION,
                step: function(now, fx) {
                    if(fx.prop != "height") return;
                    window_adjuster();
                }
            };
            var action_list = $.grep(metrics_list, function(elem) {
                return (elem.action == ACTION_GET_VISIBLE || elem.action == ACTION_GET_INVISIBLE);
            });
            var $action_list = $( $.map(action_list, function(elem) { return elem.$status_entry.get(); }) );
            if(no_animation) {
                $action_list.toggle();
                $action_list.attr('busybird-action', 'no-anim');
            }else {
                var $action_anim_list = $action_list.slice(0, ANIMATION_MAX);
                var $action_noanim_list = $action_list.slice(ANIMATION_MAX);
                $action_anim_list.attr('busybird-action', 'anim');
                $action_noanim_list.attr('busybird-action', 'no-anim');
                bb.detailedSlide($action_anim_list, "toggle", slide_options);
                $action_noanim_list.slice(ANIMATION_MAX).toggle();
            }
            window_adjuster();
            
            // return Deferred.repeat(ANIMATION_MAX, function(animation_index) {
            //     if(animation_index >= metrics_list.length) return;
            //     var metric_elem = metrics_list[animation_index];
            //     if(metric_elem.action == ACTION_GET_VISIBLE || metric_elem.action == ACTION_GET_INVISIBLE) {
            //         if(no_animation) {
            //             metric_elem.$status_entry.toggle();
            //             window_adjuster();
            //             metric_elem.$status_entry.attr('busybird-action', 'anim,no');
            //         }else {
            //             bb.detailedSlide(metric_elem.$status_entry, "toggle", slide_options);
            //             metric_elem.$status_entry.attr('busybird-action', 'anim');
            //         }
            //     }else {
            //         metric_elem.$status_entry.attr('busybird-action', 'none,anim');
            //     }
            // });
        });

        /////////////////////////////////
        
        // var $anchor_elem = null;
        // var min_dist_win = 0;
        // var min_dist_cursor = 0;
        // 
        // var invisible_num = 0;
        // var $statuses_container = $('#statuses');
        // var $status_entries = $statuses_container.children(".status-container");
        // var $visibles = $();
        // var $invisibles = $();
        // var inserts = [];
        // 
        // show_time("before each");
        // 
        // $status_entries.each(function(index, elem) {
        //     var $this = $(this);
        //     var entry_level = $this.attr('busybird-level');
        //     if(entry_level <= stayvisible_level && $this.css('display') != "none") {
        //         // ** search for anchor element
        //         var this_dist_win = bb.distanceToWindow($this);
        //         var this_dist_cursor = bb.distanceElems(bb.$cursor, $this);
        //         if(($anchor_elem == null)
        //            || (this_dist_win < min_dist_win)
        //            || (this_dist_win == min_dist_win && this_dist_cursor < min_dist_cursor)) {
        //             $anchor_elem = $this;
        //             min_dist_win = this_dist_win;
        //             min_dist_cursor = this_dist_cursor;
        //         }
        //     }
        //     if(entry_level <= bb.display_level) {
        //         // ** Collect visible elements
        //         $visibles = $visibles.add($this);
        //         if(invisible_num > 0) {
        //             inserts.push({"$pos_elem": $this, "num": invisible_num});
        //             invisible_num = 0;
        //         }
        //     }else {
        //         // ** Collect invisible elements
        //         $invisibles = $invisibles.add($this);
        //         invisible_num++;
        //     }
        //     return true;
        // });
        // show_time("end each");
        // 
        // var window_adjuster = null;
        // if($anchor_elem != null && !no_window_adjust) {
        //     $anchor_elem.addClass('bbtest-anchor');
        //     var relative_position_of_anchor = $anchor_elem.offset().top - $(window).scrollTop();
        //     window_adjuster = function() {
        //         $(window).scrollTop($anchor_elem.offset().top - relative_position_of_anchor);
        //     };
        // }
        // show_time("end creating window_adjuster");
        // $statuses_container.children(".hidden-status-header").remove();
        // if(window_adjuster) window_adjuster();
        // for(var i = 0 ; i < inserts.length ; i++) {
        //     inserts[i].$pos_elem.before(bb.formatHiddenStatus(inserts[i].num));
        // }
        // if(invisible_num > 0) {
        //     $statuses_container.append(bb.formatHiddenStatus(invisible_num));
        // }
        // if(window_adjuster) window_adjuster();
        // show_time("end manipulating headers");
        // var old_fx = $.fx.off;
        // if(no_animation) $.fx.off = true;
        // var options = {
        //     duration: bb.LEVEL_ANIMATION_DURATION,
        //     // step: (no_animation ? null : window_adjuster)
        //     step: function(now, fx) {
        //         if(fx.prop != "height") return;
        //         if(!no_animation && window_adjuster) window_adjuster();
        //     }
        //     // complete: window_adjuster
        // };
        // show_time("start slide");
        // bb.detailedSlide($visibles, "show", options);
        // bb.detailedSlide($invisibles, "hide", options);
        // $status_entries.promise().done(window_adjuster);
        // $.fx.off = old_fx;
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
    },
    toggleRunMode: function() {
        poller.toggleSelection("new_statuses");
        $('#bb-button-stop-mode').toggleClass("active");
        $('#bb-button-run-mode').toggleClass("active");
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
poller.changeSelection({'new_statuses': false});

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

