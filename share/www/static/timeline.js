// Javascript library specific to timeline view


bb.StatusContainer = $.extend(function(sel_container) {
    this.sel_container = sel_container;
    this.threshold_level = 0;
}, {
    ANIMATE_STATUS_MAX_NUM: 15,
    ANIMATE_STATUS_DURATION: 400,
    LOAD_STATUS_DEFAULT_COUNT_PER_PAGE: 100,
    LOAD_STATUS_DEFAULT_MAX_PAGE_NUM: 6,
    LOAD_STATUS_TRY_MAX: 3,
    _getStatusID: function($status) {
        return $status.find(".bb-status-id").text();
    },
    _formatHiddenStatusesHeader : function (invisible_num) {
        var plural = invisible_num > 1 ? "es" : "";
        return '<li class="bb-hidden-statuses-header"><span class="bb-hidden-statuses-num">'+ invisible_num +'</span> status'+plural+' hidden here.</li>';
    },
    _updateHiddenStatusesHeaders: function($statuses, hidden_header_list, window_adjuster) {
        var selfclass = this;
        if(!defined(window_adjuster)) window_adjuster = function() {};
        $statuses.filter(".bb-hidden-statuses-header").remove();
        window_adjuster();
        return bb.blockEach(hidden_header_list, 40, function(header_block) {
            $.each(header_block, function(i, header_entry) {
                if(defined(header_entry.$followed_by)) {
                    header_entry.$followed_by.before(selfclass._formatHiddenStatusesHeader(header_entry.entries.length));
                }else {
                    $statuses.filter('.bb-status').last().after(selfclass._formatHiddenStatusesHeader(header_entry.entries.length));
                }
            });
            window_adjuster();
        });
    },
    _createWindowAdjuster: function(dom_anchor_elem) {
        var $anchor_elem;
        var relative_position_of_anchor;
        if(!defined(dom_anchor_elem)) {
            return function() {};
        }
        $anchor_elem = $(dom_anchor_elem);
        relative_position_of_anchor = $anchor_elem.offset().top - $(window).scrollTop();
        return function() {
            $(window).scrollTop($anchor_elem.offset().top - relative_position_of_anchor);
        };
    },
    _scanStatusesForDisplayActions: function($statuses, threshold_level, enable_animation, cursor_index) {
        var selfclass = this;
        var ACTION_STAY_VISIBLE = 0;
        var ACTION_STAY_INVISIBLE = 1;
        var ACTION_BECOME_VISIBLE = 2;
        var ACTION_BECOME_INVISIBLE = 3;
        var final_result = { // ** return this struct from the promise
            hidden_header_list: [],
            doms_animate_toggle: [],
            doms_immediate_toggle: [],
            dom_anchor_elem: null,
        };
        var metrics_list = [];
        var next_seq_invisible_entries = [];
        var prev_pos = 0;
        var win_dim = {"top": $(window).scrollTop(), "range": $(window).height()};
        if(!cursor_index) cursor_index = 0;
        return bb.blockEach($statuses.filter(".bb-status").get(), 150, function(status_block, block_start_index) {
            $.each(status_block, function(index_in_block, cur_entry) {
                var cur_index = block_start_index + index_in_block;
                var $cur_entry = $(cur_entry);
                var entry_level = $cur_entry.data('bb-status-level');
                var cur_is_visible = ($cur_entry.css('display') !== 'none');
                var cur_pos = (cur_is_visible ? $cur_entry.offset().top : prev_pos);
                var metric = {
                    status_entry: cur_entry,
                    action: null,
                    win_dist: 0,
                    cursor_index_dist: 0
                };
                if(entry_level >= threshold_level) {
                    metric.action = (cur_is_visible ? ACTION_STAY_VISIBLE : ACTION_BECOME_VISIBLE);
                    if(next_seq_invisible_entries.length > 0) {
                        final_result.hidden_header_list.push({'$followed_by': $cur_entry, 'entries': next_seq_invisible_entries});
                        next_seq_invisible_entries = [];
                    }
                }else {
                    metric.action = (cur_is_visible ? ACTION_BECOME_INVISIBLE : ACTION_STAY_INVISIBLE);
                    next_seq_invisible_entries.push($cur_entry);
                }
                metric.win_dist = bb.distanceRanges(win_dim.top, win_dim.range, cur_pos, $cur_entry.height());
                metric.cursor_index_dist = Math.abs(cur_index - cursor_index);
                prev_pos = cur_pos;
                metrics_list.push(metric);
            });
        }).then(function() {
            var animate_count_max = enable_animation ? selfclass.ANIMATE_STATUS_MAX_NUM : 0;
            var animate_count = 0;
            if(next_seq_invisible_entries.length > 0) {
                final_result.hidden_header_list.push({'$followed_by': null, 'entries': next_seq_invisible_entries});
            }
            metrics_list = metrics_list.sort(function (a, b) {
                if(a.win_dist !== b.win_dist) {
                    return a.win_dist - b.win_dist;
                }
                return a.cursor_index_dist - b.cursor_index_dist;
            });
            $.each(metrics_list, function(metrics_index, metric) {
                var target_container;
                if(final_result.dom_anchor_elem === null && metric.action === ACTION_STAY_VISIBLE) {
                    final_result.dom_anchor_elem = metric.status_entry;
                }
                if(metric.action === ACTION_STAY_VISIBLE || metric.action === ACTION_STAY_INVISIBLE) {
                    return true;
                }
                if(animate_count < animate_count_max) {
                    animate_count++;
                    target_container = final_result.doms_animate_toggle;
                }else {
                    target_container = final_result.doms_immediate_toggle;
                }
                target_container.push(metric.status_entry);
            });
            return final_result;
        });
    },
    setDisplayByThreshold: function(args) {
        // @params: args.$statuses, args.threshold, args.enable_animation, args.enable_window_adjust, args.cursor_index
        // @returns: promise for completion event.
        var selfclass = this;
        return Q.fcall(function() {
            if(!defined(args.$statuses)) {
                throw "$statuses param is mandatory";
            }
            if(!defined(args.threshold)) {
                throw "threshold param is mandatory";
            }
            return selfclass._scanStatusesForDisplayActions(args.$statuses, args.threshold, args.enable_animation, args.cursor_index);
        }).then(function(action_description) {
            var window_adjuster, promise_hidden_statuses, promise_animation, promise_immeidate;
            if(args.enable_window_adjust) {
                window_adjuster = selfclass._createWindowAdjuster(action_description.dom_anchor_elem);
            }else {
                window_adjuster = function() {};
            }
            if(action_description.doms_animate_toggle.length > 0) {
                promise_animation = bb.slideToggleElements(
                    $(action_description.doms_animate_toggle), selfclass.ANIMATE_STATUS_DURATION,
                    function(now, fx) {
                        if(fx.prop !== "height") return;
                        window_adjuster();
                    }
                );
            }else {
                promise_animation = Q.fcall(function() { });
            }
            promise_hidden_statuses = selfclass._updateHiddenStatusesHeaders(args.$statuses,
                                                                             action_description.hidden_header_list,
                                                                             window_adjuster);
            promise_immediate = bb.blockEach(action_description.doms_immediate_toggle, 100, function(status_block) {
                $(status_block).toggle();
                window_adjuster();
            });
            return Q.all([promise_hidden_statuses, promise_animation, promise_immediate]);
        });
    },
    loadStatuses: function(args) {
        // @params: args.apiURL, args.ackState = "any",
        //          args.countPerPage = LOAD_STATUS_DEFAULT_COUNT_PER_PAGE,
        //          args.startMaxID = null, args.maxPageNum = LOAD_STATUS_DEFAULT_MAX_PAGE_NUM
        // @returns: a promise holding the following object in success
        //           { maxReached: (boolean), numRequests: (number of requests sent), statuses: (array of status DOM elements) }
        var selfclass = this;
        return Q.fcall(function() {
            if(!defined(args.apiURL)) {
                throw "apiURL param is mandatory";
            }
            var api_url = args.apiURL;
            var max_page_num = defined(args.maxPageNum) ? args.maxPageNum : selfclass.LOAD_STATUS_DEFAULT_MAX_PAGE_NUM;
            if(max_page_num <= 0) {
                throw "maxPageNum param must be greater than 0";
            }
            var query_params = {
                "ack_state": defined(args.ackState) ? args.ackState : "any",
                "count": defined(args.countPerPage) ? args.countPerPage : selfclass.LOAD_STATUS_DEFAULT_COUNT_PER_PAGE,
            };
            if(query_params.count <= 0) {
                throw "countPerPage param must be greater than 0";
            }
            if(defined(args.startMaxID)) {
                query_params.max_id = args.startMaxID;
            }
            var request_num = 0;
            var loaded_statuses = [];
            var last_status_id = null;
            var fulfill_handler;
            var makeRequest = function() {
                return bb.ajaxRetry({
                    type: "GET", url: api_url, data: query_params, cache: false, timeout: 3000,
                    tryMax: selfclass.LOAD_STATUS_TRY_MAX, dataType: "html",
                }).promise.then(fulfill_handler);
            };
            fulfill_handler = function(statuses_str) {
                var $statuses = $(statuses_str);
                var fully_loaded = ($statuses.size() < query_params.count);
                var is_completed;
                request_num++;
                is_completed = (fully_loaded || request_num >= max_page_num);
                if(defined(last_status_id) && last_status_id === selfclass._getStatusID($statuses.first())) {
                    $statuses = $statuses.slice(1);
                }
                $.merge(loaded_statuses, $statuses.get());
                if(is_completed) {
                    return {
                        maxReached: !fully_loaded,
                        numRequests: request_num,
                        statuses: loaded_statuses
                    };
                }else {
                    if($statuses.size() > 0) {
                        last_status_id = selfclass._getStatusID($statuses.last());
                    }
                    if(defined(last_status_id)) {
                        query_params.max_id = last_status_id;
                    }
                    return makeRequest();
                }
            };
            return makeRequest();
        });
    }
});
bb.StatusContainer.prototype = {
    _setDisplayImmediately: function($target_statuses) {
        var self = this;
        var selfclass = bb.StatusContainer;
        return selfclass.setDisplayByThreshold({
            $statuses: $target_statuses,
            threshold: self.threshold_level,
            cursor_index: null // TODO: set cursor index properly
        });
    },
    appendStatuses: function($added_statuses) {
        $(this.sel_container).append($added_statuses);
        return this._setDisplayImmediately($added_statuses);
    },
    prependStatuses: function($added_statuses) {
        $(this.sel_container).prepend($added_statuses);
        return this._setDisplayImmediately($added_statuses);
    },
    setThresholdLevel: function(new_threshold) {
        var self = this;
        var selfclass = bb.StatusContainer;
        self.threshold_level = new_threshold;
        return selfclass.setDisplayByThreshold({
            $statuses: $(self.sel_container).children(),
            threshold: self.threshold_level,
            enable_animation: true,
            enable_window_adjust: true,
            cursor_index: null // TODO: set cursor index properly
        });
    },
    getThresholdLevel: function() {
        return this.threshold_level;
    },
};

