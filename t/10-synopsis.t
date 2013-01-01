use strict;
use warnings;
use Test::More;

if(!$ENV{AUTHOR_TEST}) {
    plan 'skip_all', 'Set AUTHOR_TEST env to test synopsis.';
}

eval('use Test::Synopsis');
all_synopsis_ok();




