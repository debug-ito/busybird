use 5.006;
use strict;
use warnings;
use Module::Build;
use Module::Build::Prereqs::FromCPANfile;
 
Module::Build->new(
    module_name         => 'BusyBird',
    license             => 'perl',
    dist_author         => q{Toshio Ito <toshioito@cpan.org>},
    dist_version_from   => 'lib/BusyBird.pm',
    release_status      => 'stable',
    add_to_cleanup     => [ 'BusyBird-*' ],
    recursive_test_files => 1,
    dynamic_config => 1,
    (-d "share") ? (share_dir => "share") : (),
    
    mb_prereqs_from_cpanfile(),
    
    no_index => {
        directory => ["t", "xt", "eg", "inc", "share", "benchmark"],
        file => ['README.pod', 'README.md'],
    },
    meta_add => {
        'meta-spec' => {
            version => 2,
            url => 'https://metacpan.org/pod/CPAN::Meta::Spec',
        },
        resources => {
            bugtracker => {
                web => 'https://github.com/debug-ito/busybird/issues',
            },
            repository => {
                url => 'git://github.com/debug-ito/busybird.git',
                web => 'https://github.com/debug-ito/busybird',
            },
        }
    }
)->create_build_script();
