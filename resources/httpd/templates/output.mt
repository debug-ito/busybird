<!DOCTYPE html>
<html>
  <? my %S = @_; ?>
  <head>
    <title><?= $S{name} ?> - BusyBird</title>
    <meta content='text/html; charset=UTF-8' http-equiv='Content-Type'/>
    <link rel="stylesheet" href="/static/bootstrap/css/bootstrap.min.css" type="text/css" media="screen" />
    <link rel="stylesheet" href="/static/busybird.css" type="text/css" media="screen" />
    <link rel="stylesheet" href="/static/bootstrap/css/bootstrap-responsive.min.css" type="text/css" media="screen" />
  </head>
  <body>
    <div class="navbar navbar-fixed-top">
      <div class="navbar-inner">
        <div class="container">
          <a class="brand" href="#">BusyBird</a>
          <ul class="nav pull-left">
            <li class="active"><a><?= $S{name} ?></a></li>
            <li class="divider-vertical"></li>
          </ul>
          <div class="navbar-form pull-left">
            <a class="btn btn-small btn-inverse disabled bb-new-status-loader-button" href="#">New [ <span class="bb-new-status-num">0</span> ]</a>
          </div>
          <ul class="nav pull-right">
            <li><a><i class="icon-play icon-white"></i></a></li>
            <li class="divider-vertical"></li>
            <li><a><i class="icon-zoom-in icon-white"></i></a></li>
            <li><a><i class="icon-zoom-out icon-white"></i></a></li>
            <li class="divider-vertical"></li>
            <li><a><i class="icon-pencil icon-white"></i></a></li>
          </ul>
        </div>
      </div>
    </div>

    <div class="container">
      <div class="row">
        <div class="span2">
          place holder..
        </div>
        <div class="span8">
          <ul id="statuses" class="unstyled">
          </ul>
          <div id="main_footer">
            <button class="btn" id="more_button" type="button" onclick="" >More...</button>
          </div>
        </div>
      </div>
      <div class="row">
        <div class="span12">
          Powered by <a href="http://twitter.github.com/bootstrap/">Bootstrap, from Twitter</a>
        </div>
      </div>
    </div>
    
    <script type="text/javascript" src="/static/jquery.js"></script>
    <script type="text/javascript" src="/static/jsdeferred.nodoc.js"></script>
    <script type="text/javascript" src="/static/main.js"></script>
    <script type="text/javascript" src="/static/bootstrap/js/bootstrap.min.js"></script>
  </body>
</html>



