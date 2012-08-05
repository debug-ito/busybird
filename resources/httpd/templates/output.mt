<!DOCTYPE html>
<html>
  <? my %S = @_; ?>
  <head>
    <title><?= $S{name} ?> - BusyBird</title>
    <meta content="text/html; charset=UTF-8" http-equiv="Content-Type"/>
    <link rel="stylesheet" href="/static/bootstrap/css/bootstrap.min.css" type="text/css" media="screen" />
    <link rel="stylesheet" href="/static/busybird.css" type="text/css" media="screen" />
    <link rel="stylesheet" href="/static/bootstrap/css/bootstrap-responsive.min.css" type="text/css" media="screen" />
  </head>
  <body>
    <div class="navbar navbar-fixed-top">
      <div class="navbar-inner">
        <div class="container-fluid">
          <a class="brand" href="#">BusyBird</a>
          <ul class="nav pull-left">
            <li class="active"><a><?= $S{name} ?></a></li>
            <li class="divider-vertical"></li>
          </ul>
          <div class="navbar-form pull-left">
            <a class="btn btn-small btn-inverse disabled bb-new-status-loader-button" href="#">New <span class="bb-new-status-num badge">0</span></a>
          </div>
          <div class="navbar-form pull-right">
            <div class="btn-group pull-right">
              <a class="btn btn-inverse"><i class="icon-pencil icon-white"></i></a>
            </div>
            <div class="btn-group pull-right">
              <a class="btn btn-inverse" href="javascript: bbui.changeDisplayLevel(+1);"><i class="icon-zoom-in icon-white"></i></a>
              <a class="btn btn-inverse" href="javascript: bbui.changeDisplayLevel(-1);"><i class="icon-zoom-out icon-white"></i></a>
              <span class="label bb-nav-text pull-right">Lv. <span class="display-level">0</span></span>
            </div>
            
            <div class="btn-group pull-right" data-toggle="buttons-radio">
              <a class="btn btn-inverse active"><i class="icon-pause icon-white"></i></a>
              <a class="btn btn-inverse"><i class="icon-play icon-white"></i></a>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="container-fluid">
      <div class="row-fluid">
        <div class="span2">
          <div class="sidebar-nav sidebar-nav-fixed accordion" id="sidebar">
          </div>
        </div>
        <div class="span8">
          <ul id="statuses" class="unstyled">
          </ul>
          <div id="main-footer">
            <a class="btn btn-primary" id="more-button" data-loading-text="Loading..." href="#">More...</a>
          </div>
        </div>
      </div>
      <div class="row-fluid">
        <div class="span12">
          Powered by <a href="http://twitter.github.com/bootstrap/">Bootstrap, from Twitter</a>
        </div>
      </div>
    </div>
    
    <script type="text/javascript" src="https://ajax.googleapis.com/ajax/libs/jquery/1.7.2/jquery.min.js"></script>
    <script type="text/javascript" src="/static/jsdeferred.nodoc.js"></script>
    <script type="text/javascript" src="/static/main.js"></script>
    <script type="text/javascript" src="/static/bootstrap/js/bootstrap.min.js"></script>
  </body>
</html>



