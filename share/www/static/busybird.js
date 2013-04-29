"use strict";

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
    var dist_top = a_top  - b_top;
    var dist_btm = b_btm - a_btm;
    var signed_dist = (dist_top > dist_btm ? dist_top : dist_btm);
    return (signed_dist > 0 ? signed_dist : 0);
};

bb.slideToggleElements = function($elements, duration, step_func) {
    var deferred = Q.defer();
    if(!step_func) {
        step_func = function(now, fx) {};
    }
    $elements.animate(
        { "height": "toggle",
          "marginTop": "toggle",
          "marginBottom": "toggle",
          "paddingTop": "toggle",
          "paddingBottom": "toggle"
        },
        {
            duration: duration,
            step: step_func
        }
    ).promise().done(function() {
        deferred.resolve();
    }).fail(function() {
        deferred.reject("Animation somehow failed.");
    });
    return deferred.promise;
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


