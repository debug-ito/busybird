"use strict";

// Javascript library specific to timeline view


bb.StatusContainer = (function() { var selfclass = $.extend(function(args) {
    // @params: args.selectorContainer, args.timeline, args.apiBase = ""
    var self = this;
    if(!defined(args.selectorContainer)) {
        throw "selectorContainer param is mandatory";
    }
    if(!defined(args.timeline)) {
        throw "timeline param is mandatory";
    }
    self.sel_container = args.selectorContainer;
    self.timeline = args.timeline;
    self.api_base = defined(args.apiBase) ? args.apiBase : "";
    self.threshold_level = 0;
    self.$cursor = null;
    self.on_threshold_level_changed_callbacks = [];
    $(self.sel_container).on("click", ".bb-status", function() {
        self.setCursor(this);
        return false;
    });
}, {
    ADD_STATUSES_BLOCK_SIZE: 100,
    ANIMATE_STATUS_MAX_NUM: 15,
    ANIMATE_STATUS_DURATION: 400,
    LOAD_STATUS_DEFAULT_COUNT_PER_PAGE: 100,
    LOAD_STATUS_DEFAULT_MAX_PAGE_NUM: 6,
    LOAD_STATUS_TRY_MAX: 3,
    ACK_TRY_MAX: 3,
    LOAD_MORE_STATUSES_COUNT: 20,
    _getStatusID: function($status) {
        return $status.find(".bb-status-id").text();
    },
    _formatHiddenStatusesHeader : function (invisible_num) {
        var plural = invisible_num > 1 ? "es" : "";
        return '<li class="bb-hidden-statuses-header"><span class="bb-hidden-statuses-num">'+ invisible_num +'</span> status'+plural+' hidden here.</li>';
    },
    _updateHiddenStatusesHeaders: function($statuses, hidden_header_list, window_adjuster) {
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
        var ACTION_STAY_VISIBLE = 0;
        var ACTION_STAY_INVISIBLE = 1;
        var ACTION_BECOME_VISIBLE = 2;
        var ACTION_BECOME_INVISIBLE = 3;
        var final_result = { // ** return this struct from the promise
            hiddenHeaderList: [],
            domsAnimateToggle: [],
            domsImmediateToggle: [],
            domAnchorElem: null,
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
                        final_result.hiddenHeaderList.push({'$followed_by': $cur_entry, 'entries': next_seq_invisible_entries});
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
                final_result.hiddenHeaderList.push({'$followed_by': null, 'entries': next_seq_invisible_entries});
            }
            metrics_list = metrics_list.sort(function (a, b) {
                if(a.win_dist !== b.win_dist) {
                    return a.win_dist - b.win_dist;
                }
                return a.cursor_index_dist - b.cursor_index_dist;
            });
            $.each(metrics_list, function(metrics_index, metric) {
                var target_container;
                if(final_result.domAnchorElem === null && metric.action === ACTION_STAY_VISIBLE) {
                    final_result.domAnchorElem = metric.status_entry;
                }
                if(metric.action === ACTION_STAY_VISIBLE || metric.action === ACTION_STAY_INVISIBLE) {
                    return true;
                }
                if(animate_count < animate_count_max) {
                    animate_count++;
                    target_container = final_result.domsAnimateToggle;
                }else {
                    target_container = final_result.domsImmediateToggle;
                }
                target_container.push(metric.status_entry);
            });
            return final_result;
        });
    },
    setDisplayByThreshold: function(args) {
        // @params: args.$statuses, args.threshold, args.enableAnimation, args.enableWindowAdjust, args.cursorIndex
        // @returns: promise for completion event.
        return Q.fcall(function() {
            if(!defined(args.$statuses)) {
                throw "$statuses param is mandatory";
            }
            if(!defined(args.threshold)) {
                throw "threshold param is mandatory";
            }
            return selfclass._scanStatusesForDisplayActions(args.$statuses, args.threshold, args.enableAnimation, args.cursorIndex);
        }).then(function(action_description) {
            var window_adjuster, promise_hidden_statuses, promise_animation, promise_immediate;
            if(args.enableWindowAdjust) {
                window_adjuster = selfclass._createWindowAdjuster(action_description.domAnchorElem);
            }else {
                window_adjuster = function() {};
            }
            if(action_description.domsAnimateToggle.length > 0) {
                promise_animation = bb.slideToggleElements(
                    $(action_description.domsAnimateToggle), selfclass.ANIMATE_STATUS_DURATION,
                    function(now, fx) {
                        if(fx.prop !== "height") return;
                        window_adjuster();
                    }
                );
            }else {
                promise_animation = Q.fcall(function() { });
            }
            promise_hidden_statuses = selfclass._updateHiddenStatusesHeaders(args.$statuses,
                                                                             action_description.hiddenHeaderList,
                                                                             window_adjuster);
            promise_immediate = bb.blockEach(action_description.domsImmediateToggle, 100, function(status_block) {
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
                var $statuses = $(statuses_str).filter(".bb-status");
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
}); selfclass.prototype = {
    _setDisplayImmediately: function($target_statuses) {
        var self = this;
        return selfclass.setDisplayByThreshold({
            $statuses: $target_statuses,
            threshold: self.threshold_level,
            cursorIndex: self._getCursorIndex()
        });
    },
    _getLoadStatusesURL: function() {
        return this.api_base + "/timelines/" + this.timeline + "/statuses.html";
    },
    _getStatuses: function() {
        return $(this.sel_container).children(".bb-status");
    },
    _ackStatuses: function(acked_statuses_dom, set_max_id) {
        var self = this;
        if(acked_statuses_dom.length <= 0) {
            return Q.fcall(function() {});
        }
        var ack_ids = $.map(acked_statuses_dom, function(status_dom) {
            return selfclass._getStatusID($(status_dom));
        });
        var query_object = {"ids": ack_ids};
        if(set_max_id) {
            query_object["max_id"] = selfclass._getStatusID($(acked_statuses_dom[acked_statuses_dom.length-1]));
        }
        return bb.ajaxRetry({
            type: "POST", url: self.api_base + "/timelines/" + self.timeline + "/ack.json",
            data: JSON.stringify(query_object), contentType: "application/json",
            cache: false, timeout: 3000, dataType: "json", tryMax: selfclass.ACK_TRY_MAX
        }).promise;
    },
    _addStatuses: function(added_statuses_dom, is_prepend) {
        var self = this;
        var $container = $(self.sel_container);
        var $next_top = null;
        return bb.blockEach(added_statuses_dom, selfclass.ADD_STATUSES_BLOCK_SIZE, function(statuses_block) {
            var $statuses = $(statuses_block);
            $statuses.css("display", "none");
            if(defined($next_top)) {
                $next_top.after($statuses);
            }else {
                if(is_prepend) {
                    $container.prepend($statuses);
                }else {
                    $container.append($statuses);
                }
            }
            $next_top = $statuses.last();
        }).then(function() {
            return self._setDisplayImmediately($(added_statuses_dom));
        });
    },
    _isValidForCursor: function($status) {
        var self = this;
        return ($status.data("bb-status-level") >= self.threshold_level);
    },
    _adjustCursor: function() {
        var self = this;
        var $statuses;
        var $next_candidate, $prev_candidate;
        if(!defined(self.$cursor)) {
            $statuses = self._getStatuses();
            if($statuses.size() === 0) return;
            self.setCursor($statuses.get(0));
        }
        if(self._isValidForCursor(self.$cursor)) {
            return;
        }
        $next_candidate = self.$cursor;
        $prev_candidate = self.$cursor;
        while(true) {
            $next_candidate = $next_candidate.next(".bb-status");
            $prev_candidate = $prev_candidate.prev(".bb-status");
            if($next_candidate.size() === 0 && $prev_candidate.size() === 0) {
                return;
            }
            if($next_candidate.size() === 1 && self._isValidForCursor($next_candidate)) {
                self.setCursor($next_candidate.get(0));
                return
            }
            if($prev_candidate.size() === 1 && self._isValidForCursor($prev_candidate)) {
                self.setCursor($prev_candidate.get(0));
                return;
            }
        }
    },
    _getCursorIndex: function() {
        var self = this;
        if(!defined(self.$cursor)) return -1;
        var $statuses = self._getStatuses();
        if($statuses.size() === 0) return -1;
        return $statuses.index(self.$cursor);
    },
    appendStatuses: function(added_statuses_dom) {
        // @returns: promise resolved when done.
        return this._addStatuses(added_statuses_dom, false);
    },
    prependStatuses: function(added_statuses_dom) {
        // @returns: promise resolved when done.
        return this._addStatuses(added_statuses_dom, true);
    },
    setThresholdLevel: function(new_threshold) {
        // @returns: promise resolved when done.
        var self = this;
        var old_threshold = self.threshold_level;
        self.threshold_level = new_threshold;
        self._adjustCursor();
        if(old_threshold !== new_threshold) {
            $.each(self.on_threshold_level_changed_callbacks, function(i, callback) {
                callback(new_threshold);
            });
        }
        return selfclass.setDisplayByThreshold({
            $statuses: $(self.sel_container).children(),
            threshold: self.threshold_level,
            enableAnimation: true,
            enableWindowAdjust: true,
            cursorIndex: self._getCursorIndex()
        });
    },
    getThresholdLevel: function() {
        return this.threshold_level;
    },
    getTimelineName: function() { return this.timeline },
    getAPIBase: function() { return this.api_base },
    loadUnackedStatuses: function() {
        // @returns: promise with the following object
        //           { maxReached: (boolean), statuses: (array of status DOM elements loaded) }
        var self = this;
        var load_result;
        return selfclass.loadStatuses({
            apiURL: self._getLoadStatusesURL(),
            ackState: "unacked",
        }).then(function(result) {
            load_result = result;
            return self._ackStatuses(load_result.statuses, load_result.maxReached);
        }).then(function() {
            return self.prependStatuses(load_result.statuses);
        }).then(function() {
            return {maxReached: load_result.maxReached, statuses: load_result.statuses};
        });
    },
    loadMoreStatuses: function() {
        // @returns: promise resolved when done
        var self = this;
        var start_id = null;
        return Q.fcall(function() {
            var $statuses = self._getStatuses();
            if($statuses.size() > 0) {
                start_id = selfclass._getStatusID($statuses.last());
            }
            return selfclass.loadStatuses({
                apiURL: self._getLoadStatusesURL(),
                ackState: "any", countPerPage: selfclass.LOAD_MORE_STATUSES_COUNT,
                startMaxID: start_id, maxPageNum: 1
            });
        }).then(function(result) {
            var added_statuses = result.statuses;
            if(defined(start_id) && added_statuses.length > 0
               && selfclass._getStatusID($(added_statuses[0])) === start_id) {
                added_statuses.shift();
            }
            return self.appendStatuses(result.statuses);
        });
    },
    loadInit: function() {
        // @returns: promise with the following object
        //           { maxReached: (boolean), statuses: (array of unacked status DOM elements loaded) }
        var self = this;
        var unacked_load_result;
        return self.loadUnackedStatuses().then(function(result) {
            self._adjustCursor();
            unacked_load_result = result;
            if(!result.maxReached) {
                return self.loadMoreStatuses();
            }
        }).then(function() {
            return unacked_load_result;
        });
    },
    setCursor: function(cursor_dom) {
        var self = this;
        if(defined(self.$cursor)) {
            self.$cursor.removeClass("bb-status-cursor");
        }
        self.$cursor = $(cursor_dom);
        self.$cursor.addClass("bb-status-cursor");
    },
    listenOnThresholdLevelChanged: function(callback) {
        // @params: callback (function(new_threshold) returning anything)
        this.on_threshold_level_changed_callbacks.push(callback);
    },
}; return selfclass;})();

////////////////////////////////////////////////////////

bb.TimelineUnackedCountsPoller = (function() {
    var selfclass = $.extend(function(args) {
        // @params: args.statusContainer
        var scon = args.statusContainer;
        if(!defined(scon)) {
            throw "statusContainer param is mandatory";
        }
        this.status_container = scon;
        this.url = scon.getAPIBase() + "/timelines/" + scon.getTimelineName() + "/updates/unacked_counts.json";
        this.initial_query = this._makeQuery({});
        this.on_change_listeners = [];
    }, {
        LEVEL_MARGIN: 2,
    });
    selfclass.prototype = $.extend(
        new bb.EventPoller({
            onResponse: function(response_data) {
                var self = this;
                if(defined(response_data.error)) {
                    self._onError(response_data.error);
                    return;
                }
                $.each(self.on_change_listeners, function(i, listener) {
                    listener(response_data.unacked_counts);
                });
                return self._makeQuery(response_data.unacked_counts);
            }
        }),
        {
            _onError: function(error_message) { console.log(error_message) },
            _setQueryItem: function(target_query_object, current_unacked_counts, key) {
                var self = this;
                var cur_value = current_unacked_counts[key];
                target_query_object[key] = defined(cur_value) ? cur_value : 0;
            },
            _makeQuery: function(current_unacked_counts) {
                var self = this;
                var query = {};
                var threshold = self.status_container.getThresholdLevel();
                var level;
                if(!defined(current_unacked_counts)) {
                    current_unacked_counts = {};
                }
                self._setQueryItem(query, current_unacked_counts, "total");
                for(level = threshold - selfclass.LEVEL_MARGIN ; level <= threshold + selfclass.LEVEL_MARGIN ; level++) {
                    self._setQueryItem(query, current_unacked_counts, level);
                }
                return query;
            },
            listenOnChange: function(callback) {
                // @params: callback (function(unacked_counts))
                this.on_change_listeners.push(callback);
            }
        }
    );
    return selfclass;
})();

