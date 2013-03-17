use inc::Module::Install;

name     'BusyBird';
all_from 'lib/BusyBird.pm';
author   q{Toshio ITO <toshioito@cpan.org>};
license  'perl';

requires 'Async::Queue', '0.02';
requires 'Async::Selector', '1.03';
requires 'Async::Selector::Aggregator', '1.02';
requires 'CPS', '0.15';
requires 'CPS::Functional', '0.15';
requires 'Carp', '0';
requires 'DateTime', '0.70';
requires 'DateTime::Duration', '0';
requires 'DateTime::Format::Strptime', '0';
requires 'DateTime::TimeZone', '1.42';
requires 'Encode', '0';
requires 'Exporter', '0';
requires 'File::ShareDir', '0';
requires 'File::Spec', '0';
requires 'JSON', '0';
requires 'List::Util', '1.24';
requires 'Plack::Builder', '0';
requires 'Plack::Request', '0';
requires 'Router::Simple', '0';
requires 'Scalar::Util', '1.24';
requires 'Storable', '2.27';
requires 'Test::Builder', '0';
requires 'Test::Exception', '0';
requires 'Test::More', '0.98';
requires 'Text::Xslate', '1.60';
requires 'Tie::IxHash', '0';
requires 'Time::HiRes', '1.9720';
requires 'Try::Tiny', '0.10';
requires 'autovivification', '0.10';

test_requires 'FindBin', '0';
test_requires 'HTTP::Request', '6.00';
test_requires 'Plack::Test', '0';
test_requires 'Test::Builder', '0';
test_requires 'Test::Exception', '0.31';
test_requires 'Test::Memory::Cycle', '1.04';
test_requires 'Test::MockObject', '1.09';
test_requires 'Test::More', '0.98';
test_requires 'Test::Warn', '0.24';
test_requires 'HTML::TreeBuilder', '5';
test_requires 'HTML::TreeBuilder::XPath', '0.12';


## auto_install;

repository 'https://github.com/debug-ito/busybird';

tests_recursive;
install_share;

WriteAll;
