"use strict";

// Javascript library for timeline list view.

bb.UnackedCountsRenderer = (function() {
    var selfclass = function(args) {
        // @params: args.domTarget, args.levelNum = 2
        this.dom_target = args.domTarget;
        this.level_num = defined(args.levelNum) ? args.levelNum : 2;
    };
    selfclass.prototype = {
        _renderLevel: function(level, sum_count, this_count) {
            var $pair = $('<span class="bb-unacked-counts-pair"></span>');
            var $level = $('<span class="bb-unacked-counts-level"></span>');
            var $sum_count = $('<span class="bb-unacked-counts-sum-count badge badge-info"></span>').text(sum_count);
            if(level === 'total') {
                $level.text("Total");
            }else {
                $pair.append("Lv. ");
                $level.text(level);
            }
            $pair.append($level).append(" ").append($sum_count);
            if(defined(this_count)) {
                $pair.append(" ").append($('<span class="bb-unacked-counts-this-count badge"></span>').text("+" + this_count));
            }
            return $pair;
        },
        show: function(unacked_counts) {
            // @returns: nothing
            var self = this;
            var total = unacked_counts.total;
            var leveled_counts = [];
            var $target = $(self.dom_target);
            var sum_count = null;
            $target.empty();
            if(total === 0) {
                $target.append(self._renderLevel("total", total));
                return;
            }
            delete unacked_counts.total;
            $.each(unacked_counts, function(level, count) {
                leveled_counts.push({level: parseInt("" + level, 10), count: count});
            });
            leveled_counts.sort(function(a, b) {
                return b.level - a.level;
            });
            $.each(leveled_counts, function(i, count_entry) {
                if(i >= self.level_num) {
                    return false;
                }
                if(defined(sum_count)) {
                    sum_count += count_entry.count;
                    $target.append(self._renderLevel(count_entry.level, sum_count, count_entry.count));
                }else {
                    sum_count = count_entry.count;
                    $target.append(self._renderLevel(count_entry.level, sum_count));
                }
            });
            if(leveled_counts.length > self.level_num) {
                $target.append(self._renderLevel("total", total, total - sum_count));
            }
        }
    };
    return selfclass;
})();

