//// BusyBird main library
//// Copyright (c) 2013 Toshio ITO


function defined(val){
    // ** simulate Perl's defined() function.
    return !(val === null || typeof(val) === 'undefined');
}

var bb = {};

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
