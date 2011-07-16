use strict;
use warnings;
use ExtUtils::MakeMaker;
use File::ShareDir::Install;
use Alien::SDL;
use OpenGL::Config;

install_share 'res';

WriteMakefile(
    NAME                => 'Games::Construder',
    AUTHOR              => 'Robin Redeker <elmex@ta-sa.org>',
    LICENSE             => 'agpl_3',
    VERSION_FROM        => 'lib/Games/Construder.pm',
    ABSTRACT_FROM       => 'lib/Games/Construder.pm',
    PL_FILES            => {},
    EXE_FILES           => [qw(bin/construder_server bin/construder_client)],
    LIBS                => [Alien::SDL->config('libs')],
    INC                 => Alien::SDL->config('cflags'),
    dynamic_lib  => {
       OTHERLDFLAGS =>
          # Hack, to make it work on windows "somehow" :-)
          Alien::SDL->config('libs') . " " . $OpenGL::Config->{LIBS}
          . ($^O eq 'MSWin32'
                ? " -lopengl32 -lglu32 -L\"C:\\strawberry\\perl\\site\\bin\" -lfreeglut "
                : "")
    },
    (CCFLAGS  => Alien::SDL->config('cflags') . " " . $OpenGL::Config->{INC}),
    test                => { TESTS => "t/*.t t/methds/*.t" },
    CONFIGURE_REQUIRES => {
      'File::ShareDir::Install' => 0,
      'Alien::SDL'              => 0,
      'OpenGL'                  => 0,
    },
    PREREQ_PM => {
      # For now try to require them for runtime too:
      # (Seems old cpans don't know about CONFIGURE_REQUIRES...)
      'File::ShareDir::Install' => 0,
      'Alien::SDL'              => 0,
      'OpenGL'                  => 0,

      'Test::More'          => 0,
      'Object::Event'       => 0,
      'common::sense'       => 0,
      'AnyEvent'            => 0,
      'JSON'                => 0,
      'OpenGL'              => 0,
      'OpenGL::List'        => 0,
      'SDL'                 => 0,
      'Math::Trig'          => 0,
      'Compress::LZF'       => 0,
      'File::ShareDir::PAR' => 0,
      'Storable'            => 0,
    },
    META_MERGE => {
      resources => {
         repository => {
            web => "http://git.ta-sa.org/git/Games-Construder/",
            url => "http://git.ta-sa.org/Games-Construder.git",
            type => "git",
         },
         bugtracker => {
            web => "http://ue.o---o.eu/",
            mailto => "elmex\@ta-sa.org",
         },
         homepage => "http://ue.o---o.eu/",
      }
    },
    depend => {
       "Construder.c" => "vectorlib.c world.c world_data_struct.c render.c queue.c "
                       . "world_drawing.c noise_3d.c volume_draw.c light.c counters.c"
    },
    dist                => {
       COMPRESS => 'gzip -9f',
       SUFFIX   => 'gz',
       PREOP => 'pod2text lib/Games/Construder.pm | tee README >$(DISTVNAME)/README; chmod -R u=rwX,go=rX . ;',
    },
    clean               => { FILES => 'Games-Construder' },
);

package MY;
use File::ShareDir::Install qw(postamble);
