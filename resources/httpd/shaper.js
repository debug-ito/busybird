var current_level = 1;
var MAX_LEVEL = 5;

var cursor = 0;

$(document).ready(init);

function init() {
  adjustPlaceHolder();
  $(document).keypress(keyHandler);
}

function adjustPlaceHolder() {
  $('div#control_placehold').height($('div#control').height());
}

function keyHandler(event) {
  //alert("which: " + event.which + " , keyCode: " + event.keyCode + " , charCode:" + event.charCode);
  switch(event.which) {
  case 104: // h
    changeLevel(current_level - 1, "box_" + cursor)
    break;
  case 106: // j
    cursorSlide(+1);
    break;
  case 107: // k
    cursorSlide(-1);
    break;
  case 108: //l
    changeLevel(current_level + 1, "box_" + cursor);
    break;
  }
}

function setWindowToElement(elem) {
  elem_y = elem.offsetTop;
  set_y = elem_y - $(window).height() / 2.0;
  if(set_y < 0) set_y = 0;
  $(window).scrollTop(set_y);
}

function getAnchorElement(to_level, anchor_target) {
  anchor_level = current_level > to_level ? to_level : current_level;
  status_list = getStatusArrayForLevel(anchor_level);
  min_diff_y = Math.abs(status_list[0].offsetTop - anchor_target);
  min_diff_obj = status_list[0];
  for(i = 1 ; i < status_list.length ; i++) {
    diff_y = Math.abs(status_list[i].offsetTop - anchor_target);
    if(diff_y < min_diff_y) {
      min_diff_y = diff_y;
      min_diff_obj = status_list[i];
    }
  }
  return min_diff_obj;
}

function getStatusArrayForLevel(level) {
  var status_arr = new Array();
  for(temp_level = 1 ; temp_level <= level ; temp_level++) {
    status_arr = jQuery.merge(status_arr, $("div.status_lv" + temp_level));
    // status_arr = $("div.status_lv" + temp_level);
  }
  return status_arr;
}

function changeCursor(to_cursor) {
  $("#box_" + cursor).removeClass("cursor");
  $("#box_" + to_cursor).addClass("cursor");
  cursor = to_cursor;
}

function changeLevel(to_level, target_id) {
  var level;
  if(to_level <= 0 || to_level > MAX_LEVEL) return;

  var anchor_target;
  if(target_id == "") {
    anchor_target = $(window).scrollTop() + $('div#control').height();
  }else {
    target_elem = $("#" + target_id);
    anchor_target = target_elem.offset().top + target_elem.height() / 2
  }
  anchor_elem = getAnchorElement(to_level, anchor_target);
  anchor_relpos = anchor_elem.offsetTop - $(window).scrollTop();

  for(level = 1 ; level <= MAX_LEVEL ; level++) {
    // $("div.status_lv" + level).css("border", "1px solid red");
    if(level < to_level) {
      $("div.status_lv" + level).show();
      $("div.header_lv" + level).hide();
    }else if(level == to_level) {
      $("div.status_lv" + level).show();
      $("div.header_lv" + level).show();
    }else {
      $("div.status_lv" + level).hide();
      $("div.header_lv" + level).hide();
    }
  }
  current_level = to_level;
  $("span#cur_level").text(current_level);
  $("span#y_pos").text($("body").scrollTop());
  $("span#cur_lv_num").text(getStatusArrayForLevel(current_level).length);
  // setWindowToElement(anchor_elem);
  $(window).scrollTop(anchor_elem.offsetTop - anchor_relpos);
  changeCursor(parseInt(anchor_elem.id.substr(4)));
}

function cursorSlide(slide_direction) {
  var temp_cursor = cursor;
  while(1) {
    temp_cursor += slide_direction;
    elem = $('#box_' + temp_cursor);
    if(elem.length == 0) {
      break;
    }
    if(elem.css('display') == 'block' && elem.attr('class').indexOf("header") < 0) {
      changeCursor(temp_cursor);
      var upper_padding = $('div#control').outerHeight();
      var lower_padding = 0;
      if(elem.offset().top < $(window).scrollTop() + upper_padding) {
        $(window).scrollTop(elem.offset().top - upper_padding);
      }
      if(elem.offset().top + elem.outerHeight() > $(window).scrollTop() + $(window).height() - lower_padding) {
        $(window).scrollTop(elem.offset().top + elem.outerHeight() - $(window).height() + lower_padding);
      }
      break;
    }
  }
}

