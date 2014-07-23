use 5.006;
use strict;
use warnings;
use Module::Build::Pluggable (
    'CPANfile'
);
 
my $builder = Module::Build::Pluggable->new(
    module_name         => 'BusyBird',
    license             => 'perl',
    dist_author         => q{Toshio Ito <toshioito@cpan.org>},
    dist_version_from   => 'lib/BusyBird.pm',
    release_status      => 'stable',
    add_to_cleanup     => [ 'BusyBird-*' ],
    recursive_test_files => 1,
    no_index => {
        directory => ["t", "xt", "eg", "inc", "share", "benchmark"],
        file => ['README.pod', 'README.md'],
    },
    share_dir => "share",
    meta_add => {
        resources => {
            bugtracker => 'https://github.com/debug-ito/busybird/issues',
            repository => 'https://github.com/debug-ito/busybird',
        }
    }
);
 
$builder->create_build_script();
