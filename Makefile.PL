use strict;
use warnings;
use ExtUtils::MakeMaker;
use Alien::SDL;

WriteMakefile(
    NAME                => 'Games::Construder',
    AUTHOR              => 'Robin Redeker <elmex@ta-sa.org>',
    LICENSE             => 'perl',
    VERSION_FROM        => 'lib/Games/Construder.pm',
    ABSTRACT_FROM       => 'lib/Games/Construder.pm',
    PL_FILES            => {},
    EXE_FILES           => [qw(bin/construder_server bin/construder_client)],
    LIBS                => [Alien::SDL->config('libs')],
    INC                 => Alien::SDL->config('cflags'),
    test                => { TESTS => "t/*.t t/methds/*.t" },
    PREREQ_PM => {
        'Test::More'    => 0,
        'common::sense' => 0,
        'AnyEvent'      => 0,
        'JSON'          => 0,
        'OpenGL'        => 0,
        'OpenGL::List'  => 0,
        'SDL'           => 0,
        'Math::Trig'    => 0,
        'Compress::LZF' => 0,
    },
    depend => {
       "Construder.c" => "vectorlib.c world.c world_data_struct.c render.c world_drawing.c noise_3d.c volume_draw.c"
    },
    dist                => {
       COMPRESS => 'gzip -9f',
       SUFFIX   => 'gz',
       PREOP => 'pod2text lib/Games/Construder.pm | tee README >$(DISTVNAME)/README; chmod -R u=rwX,go=rX . ;',
    },
    clean               => { FILES => 'Games-Construder' },
);
