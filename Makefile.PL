use strict;
use warnings;
use inc::Module::Install;
use Alien::SDL;
use OpenGL::Config;

name      'Games-Construder';
author    'Robin Redeker <elmex@ta-sa.org>';
license   'gpl';
all_from  'lib/Games/Construder.pm';

makemaker_args (
    #(LIBS => Alien::SDL->config('libs')),
    dynamic_lib  => {
       OTHERLDFLAGS => Alien::SDL->config('libs') . " " . $OpenGL::Config->{LIBS}
                       . ($^O eq 'MSWin32' ? " -lopengl32 -lglu32 -L\"C:\\strawberry\\perl\\site\\bin\" -lfreeglut " : "")
    },
 #   DEFINE => $OpenGL::Config->{DEFINE},
    (CCFLAGS  => Alien::SDL->config('cflags') . " " . $OpenGL::Config->{INC}),
    depend => {
       "Construder.c" => "vectorlib.c world.c world_data_struct.c render.c queue.c "
                       . "world_drawing.c noise_3d.c volume_draw.c light.c"
    },
);

requires 'Test::More'          => 0;
requires 'Object::Event'       => 0;
requires 'common::sense'       => 0;
requires 'AnyEvent'            => 0;
requires 'JSON'                => 0;
requires 'OpenGL'              => 0;
requires 'OpenGL::List'        => 0;
requires 'SDL'                 => 0;
requires 'Math::Trig'          => 0;
requires 'Compress::LZF'       => 0;
requires 'EV'                  => 0;
requires 'File::ShareDir::PAR' => 0;
requires 'Storable'            => 0;

install_script 'bin/construder_server';
install_script 'bin/construder_client';

install_share 'res';

#make_par ();

WriteAll;

#WriteMakefile(
#    NAME                => 'Games::Construder',
#    AUTHOR              => 'Robin Redeker <elmex@ta-sa.org>',
#    LICENSE             => 'perl',
#    VERSION_FROM        => 'lib/Games/Construder.pm',
#    ABSTRACT_FROM       => 'lib/Games/Construder.pm',
#    PL_FILES            => {},
#    EXE_FILES           => [qw(bin/construder_server bin/construder_client)],
#    LIBS                => [Alien::SDL->config('libs')],
#    INC                 => Alien::SDL->config('cflags'),
#    test                => { TESTS => "t/*.t t/methds/*.t" },
#    PREREQ_PM => {
#    },
#    dist                => {
#       COMPRESS => 'gzip -9f',
#       SUFFIX   => 'gz',
#       PREOP => 'pod2text lib/Games/Construder.pm | tee README >$(DISTVNAME)/README; chmod -R u=rwX,go=rX . ;',
#    },
#    clean               => { FILES => 'Games-Construder' },
#);
