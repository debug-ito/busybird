//// BusyBird main library
//// Copyright (c) 2013 Toshio ITO


function defined(val){
    // ** simulate Perl's defined() function.
    return !(val === null || typeof(val) === 'undefined');
}

var bb = {};

bb.ajaxRetry = (function() {
    var backoff_init_ms = 500;
    var backoff_factor = 2;
    var backoff_max_ms = 120000;
    return function (ajax_param) {
        var ajax_xhr = null;
        var ajax_retry_ok = true;
        var ajax_retry_backoff = backoff_init_ms;
        var deferred = Q.defer();
        var try_max = 0;
        var try_count = 0;
        var ajax_done_handler, ajax_fail_handler;
        if('tryMax' in ajax_param) {
            try_max = ajax_param.tryMax;
            delete ajax_param.tryMax;
        }
        ajax_done_handler = function(data, textStatus, jqXHR) {
            // deferred.call(data, textStatus, jqXHR);
            deferred.resolve(data);
        };
        ajax_fail_handler = function(jqXHR, textStatus, errorThrown) {
            ajax_xhr = null;
            try_count++;
            if(try_max > 0 && try_count >= try_max) {
                // deferred.fail(jqXHR, textStatus, errorThrown);
                deferred.reject({textStatus: textStatus, errorThrown: errorThrown});
                return;
            }
            ajax_retry_backoff *= backoff_factor;
            if(ajax_retry_backoff > backoff_max_ms) {
                ajax_retry_backoff = backoff_max_ms;
            }
            setTimeout(function() {
                if(ajax_retry_ok) {
                    ajax_xhr =  $.ajax(ajax_param);
                    ajax_xhr.then(ajax_done_handler, ajax_fail_handler);
                };
            }, ajax_retry_backoff);
        };
        ajax_xhr = $.ajax(ajax_param);
        ajax_xhr.then(ajax_done_handler, ajax_fail_handler);
        return {
            promise: deferred.promise,
            cancel: function() {
                ajax_retry_ok = false;
                deferred.reject({textStatus: "cancelled", errorThrown: ""});
                console.log("ajaxRetry: canceller called");
                if(defined(ajax_xhr)) {
                    console.log("ajaxRetry: xhr aborted.");
                    ajax_xhr.abort();
                }
            }
        };
    };
})();

bb.blockEach = function(orig_array, block_size, each_func) {
    var block_num = Math.ceil(orig_array.length / block_size);
    var i;
    var start_defer = Q.defer();
    var end_promise = start_defer.promise;
    var generate_callback_for = function(block_index) {
        return function() {
            var start_global_index = block_size * block_index;
            return each_func(orig_array.slice(start_global_index, start_global_index + block_size), start_global_index);
        };
    };
    start_defer.resolve();
    for(i = 0 ; i < block_num ; i++) {
        end_promise = end_promise.then(generate_callback_for(i));
    }
    return end_promise;
};

bb.distanceRanges = function (a_top, a_range, b_top, b_range) {
    var a_btm = a_top + a_range;
    var b_btm = b_top + b_range;
    var dist_top = a_top  - b_top
    var dist_btm = b_btm - a_btm;
    var signed_dist = (dist_top > dist_btm ? dist_top : dist_btm);
    return (signed_dist > 0 ? signed_dist : 0);
};

bb.Spinner = function(sel_target) {
    this.sel_target = sel_target;
    this.spin_count = 0;
    this.spinner = new Spinner({
        lines: 10,
        length: 5,
        width: 2,
        radius: 3,
        corners: 1,
        rotate: 0,
        trail: 60,
        speed: 1.0,
        color: "#CCC",
        className: 'bb-spinner',
        left: 0,
    });
};
bb.Spinner.prototype = {
    set: function(val) {
        var old = this.spin_count;
        if(val < 0) val = 0;
        this.spin_count = val;
        if(old > 0 && this.spin_count <= 0) {
            this.spinner.stop();
        }else if(old <= 0 && this.spin_count > 0) {
            this.spinner.spin($(this.sel_target).get(0));
        }
    },
    begin: function() {
        this.set(this.spin_count + 1);
    },
    end: function() {
        this.set(this.spin_count - 1);
    }
};

bb.MessageBanner = function(sel_target) {
    this.sel_target = sel_target;
    this.timeout_obj = null;
};
bb.MessageBanner.prototype = {
    show: function(msg, type, timeout) {
        var $msg = $(this.sel_target);
        var self = this;
        if(!defined(type)) type = "normal";
        msg = '<span class="bb-msg-'+type+'">'+msg+'</span>';
        $msg.html(msg).show();
        if(!defined(timeout) || timeout <= 0) timeout = 5000;
        if(defined(self.timeout_obj)) {
            clearTimeout(self.timeout_obj);
            self.timeout_obj = null;
        }
        self.timeout_obj = setTimeout(function() {
            self.timeout_obj = null;
            $msg.fadeOut('fast');
        }, timeout);
    },
};


bb.StatusContainer = $.extend(function(sel_container) {
    this.sel_container = sel_container;
}, {
    _scanStatusesForDisplayActions: function($statuses, threshold_level, enable_animation, cursor_index) {
        var ACTION_STAY_VISIBLE = 0;
        var ACTION_STAY_INVISIBLE = 1;
        var ACTION_GET_VISIBLE = 2;
        var ACTION_GET_INVISIBLE = 3;
        var final_result = { // ** return this struct from the promise
            hidden_header_list: [],
            doms_animate_show: [],
            doms_animate_hide: [],
            doms_immediate_show: [],
            doms_immediate_hide: [],
        };
        var metrics_list = [];
        var next_seq_invisible_entries = [];
        var prev_pos;
        var win_dim;
        if(!cursor_index) cursor_index = 0;
        if(enable_animation) {
            win_dim = {"top": $(window).scrollTop(), "range": $(window).height()};
        }
        return bb.blockEach($statuses.filter(".bb-status").get(), 150, function(status_block, block_start_index) {
            $.each(status_block, function(index_in_block, cur_entry) {
                var cur_index = block_start_index + index_in_block;
                var $cur_entry = $(cur_entry);
                var entry_level = $cur_entry.data('bb-status-level');
                var cur_is_visible = ($cur_entry.css('display') !== 'none');
                var cur_pos;
                var metric = {
                    status_entry: cur_entry,
                    action: null,
                    win_dist: 0,
                    cursor_index_dist: 0
                };
                if(entry_level <= threshold_level) {
                    metric.action = (cur_is_visible ? ACTION_STAY_VISIBLE : ACTION_GET_VISIBLE);
                    if(next_seq_invisible_entries.length > 0) {
                        final_result.hidden_header_list.push({'$followed_by': $cur_entry, 'entries': next_seq_invisible_entries});
                        next_seq_invisible_entries = [];
                    }
                }else {
                    metric.action = (cur_is_visible ? ACTION_GET_INVISIBLE : ACTION_STAY_INVISIBLE);
                    next_seq_invisible_entries.push($cur_entry);
                }
                if(enable_animation) {
                    cur_pos = (cur_is_visible ? $cur_entry.offset().top : prev_pos);
                    metric.win_dist = bb.distanceRanges(win_dim.top, win_dim.range, cur_pos, $cur_entry.height());
                    metric.cursor_index_dist = Math.abs(cur_index - cursor_index);
                    prev_pos = cur_pos;
                }
                metrics_list.push(metric);
            });
        }).then(function() {
            if(next_seq_invisible_entries.length > 0) {
                final_result.hidden_header_list.push({'$followed_by': null, 'entries': next_seq_invisible_entries});
            }
            // このへんから。
        });
    },
    setDisplayByThreshold: function(args) {
        // @params: args.$statuses, args.threshold, args.enable_animation, args.enable_window_adjust
        // @returns: promise for completion event.
        return Q.fcall(function() {
            var $statuses, threshold;
            if(!defined(args.$statuses)) {
                throw "$statuses param is mandatory";
            }
            if(!defined(args.threshold)) {
                throw "threshold param is mandatory";
            }
            $statuses = args.$statuses;
            threshold = args.threshold;
            
        });
    },
    loadStatuses: function(args) {
        // @params: args.apiurl, args.ack_state, args.start_max_id, args.max_page_num
    }
});
bb.StatusContainer.prototype = {
    _formatHiddenStatus : function (invisible_num) {
        var plural = invisible_num > 1 ? "es" : "";
        return '<li class="bb-hidden-statuses-header"><span class="bb-hidden-statuses-num">'+ invisible_num +'</span> status'+plural+' hidden here.</li>';
    },
    appendStatuses: function($added_statuses) {
        $(this.sel_container).append($added_statuses);
    },
    prependStatuses: function($added_statuses) {
        $(this.sel_container).prepend($added_statuses);
    },
    setThresholdLevel: function(new_threshold) {
        
    },
    getThresholdLevel: function() {
        
    },
};

