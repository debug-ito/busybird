BusyBird: a multi-level Web-based timeline viewer
=================================================

[![Build Status](https://travis-ci.org/debug-ito/busybird.svg?branch=master)](https://travis-ci.org/debug-ito/busybird)

BusyBird is a personal Web-based timeline viewer application.
You can think of it as a Twitter client, but BusyBird is more generic and focused on viewing.

BusyBird accepts data called **Statuses** from its RESTful Web API.
The received statuses are stored to one or more **Timelines** .
You can view those statuses in a timeline by a Web browser.

For more information, visit https://metacpan.org/pod/BusyBird


INSTALLATION
------------

To install this module, run the following commands:

    $ perl Build.PL
    $ ./Build
    $ ./Build test
    $ ./Build install


AUTHOR
------

Toshio Ito

* https://github.com/debug-ito
* debug.ito [at] gmail.com
