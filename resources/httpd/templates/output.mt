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
        <div class="container-fluid">
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

    <div class="container-fluid">
      <div class="row-fluid">
        <div class="span2">
          <div class="sidebar-nav sidebar-nav-fixed accordion" id="sidebar">
            <div class="accordion-group">
              <div class="accordion-heading">
                <span class="accordion-toggle">0 new statuses loaded</span>
              </div>
            </div>
            <div class="accordion-group">
              <div class="accordion-heading">
                <a class="accordion-toggle" data-toggle="collapse" data-parent="#sidebar" href="#info-dummy1">dummy1</a>
              </div>
              <div class="accordion-body collapse" id="info-dummy1"><div class="accordion-inner sidebar-detail">
                                    Anim pariatur cliche reprehenderit, enim eiusmod high life accusamus terry richardson ad squid. 3 wolf moon officia aute, non cupidatat skateboard dolor brunch. Food truck quinoa nesciunt laborum eiusmod. Brunch 3 wolf moon tempor, sunt aliqua put a bird on it squid single-origin coffee nulla assumenda shoreditch et. Nihil anim keffiyeh helvetica, craft beer labore wes anderson cred nesciunt sapiente ea proident. Ad vegan excepteur butcher vice lomo. Leggings occaecat craft beer farm-to-table, raw denim aesthetic synth nesciunt you probably haven't heard of them accusamus labore sustainable VHS.
              </div></div>
            </div>
            <div class="accordion-group">
              <div class="accordion-heading">
                <a class="accordion-toggle" data-toggle="collapse" data-parent="#sidebar" href="#info-dummy">dummy info</a>
              </div>
              <div class="accordion-body collapse" id="info-dummy"><div class="accordion-inner sidebar-detail">
                  Anim pariatur cliche reprehenderit, enim eiusmod high life accusamus terry richardson ad squid. 3 wolf moon officia aute, non cupidatat skateboard dolor brunch. Food truck quinoa nesciunt laborum eiusmod. Brunch 3 wolf moon tempor, sunt aliqua put a bird on it squid single-origin coffee nulla assumenda shoreditch et. Nihil anim keffiyeh helvetica, craft beer labore wes anderson cred nesciunt sapiente ea proident. Ad vegan excepteur butcher vice lomo. Leggings occaecat craft beer farm-to-table, raw denim aesthetic synth nesciunt you probably haven't heard of them accusamus labore sustainable VHS.
              </div></div>
            </div>
          </div>
        </div>
        <div class="span8">
          <ul id="statuses" class="unstyled">
          </ul>
          <div id="main_footer">
            <a class="btn btn-primary" id="more_button" data-loading-text="Loading..." href="#">More...</a>
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



