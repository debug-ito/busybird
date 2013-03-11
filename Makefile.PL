use inc::Module::Install;

name     'BusyBird';
all_from 'lib/BusyBird.pm';
author   q{Toshio ITO <toshioito@cpan.org>};
license  'perl';

build_requires 'Test::More';

auto_install;

tests_recursive;
install_share;

WriteAll;

