use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Games::Blockminer3D',
    AUTHOR              => 'Robin Redeker <elmex@ta-sa.org>',
    LICENSE             => 'perl',
    VERSION_FROM        => 'lib/Games/Blockminer3D.pm',
    ABSTRACT_FROM       => 'lib/Games/Blockminer3D.pm',
    PL_FILES            => {},
    test                => { TESTS => "t/*.t t/methds/*.t" },
    PREREQ_PM => {
        'Test::More'    => 0,
        'AnyEvent'      => 3.5,
        'common::sense' => 0,
        'AnyEvent'      => 0,
        'JSON'          => 0,
        'OpenGL'        => 0,
        'OpenGL::List'  => 0,
        'SDL'           => 0,
        'Math::Trig'    => 0,
    },
    dist                => {
       COMPRESS => 'gzip -9f',
       SUFFIX   => 'gz',
       PREOP => 'pod2text lib/Games/Blockminer3D.pm | tee README >$(DISTVNAME)/README; chmod -R u=rwX,go=rX . ;',
    },
    clean               => { FILES => 'Games-Blockminer3D' },
);
