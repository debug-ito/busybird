<html>
  <? my %S = @_; ?>
  <head>
    <title><?= $S{name} ?> - BusyBird</title>
    <meta content='text/html; charset=UTF-8' http-equiv='Content-Type'/>
    <link rel="stylesheet" href="/static/bootstrap/css/bootstrap.min.css" type="text/css" media="screen" />
    <link rel="stylesheet" href="/static/bootstrap/css/bootstrap-responsive.min.css" type="text/css" media="screen" />
  </head>
  <body>
    <div class="navbar navbar-fixed-top">
      <div class="navbar-inner">
        <div class="container">
          <a class="btn btn-navbar" data-toggle="collapse" data-target=".nav-collapse">
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
          </a>
          <a class="brand" href="#">Project name</a>
          <div class="nav-collapse">
            <ul class="nav">
              <li class="active"><a href="#">Home</a></li>
              <li><a href="#about">About</a></li>
              <li><a href="#contact">Contact</a></li>
            </ul>
          </div><!--/.nav-collapse -->
        </div>
      </div>
    </div>

    <div class="container">
      <div id="global_header">
      </div>
      <div id="global_side">
      </div>
      <div id="side_container">
      </div>
      <div id="optional_container">
      </div>
      <div id="main_container">
        <ul id="statuses">
        </ul>
        <div id="main_footer">
          <button id="more_button" type="button" onclick="" >More...</button>
        </div>
      </div>
      <div id="footer">
        Powered by <a href="http://twitter.github.com/bootstrap/">Bootstrap, from Twitter</a>
      </div>
    </div>
    
    <script type="text/javascript" src="/static/jquery.js"></script>
    <script type="text/javascript"><!--
    function bbGetOutputName() {return "<?= $S{name} ?>"}
--></script>
    <script type="text/javascript" src="/static/main.js"></script>
    <script type="text/javascript" src="/static/bootstrap/js/bootstrap.min.js"></script>
  </body>
</html>



