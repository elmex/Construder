package Games::Blockminer3D::Client::Frontend;
use common::sense;
use SDL;
use SDLx::App;
use SDL::Mouse;
use SDL::Video;
use SDL::Events;
use SDL::Image;
use SDL::Event;
use OpenGL qw(:all);
use OpenGL::List;
use AnyEvent;
use Math::Trig qw/deg2rad rad2deg pi/;
use Time::HiRes qw/time/;
use POSIX qw/floor/;
use Games::Blockminer3D::Vector;

use Games::Blockminer3D::Client::World;

use base qw/Object::Event/;

=head1 NAME

Games::Blockminer3D::Client::Frontend - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Client::Frontend->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;
   $self->init_app;
   $self->init_physics;
   $self->setup_event_poller;

   return $self
}

my ($WIDTH, $HEIGHT) = (720, 400);#600, 400);

sub init_physics {
   my ($self) = @_;

   $self->{phys_obj}->{player} = {
      pos => [5.5, 3.5, 5.5],#-25, -50, -25),
      vel => [0, 0, 0],
   };
}

sub init_app {
   my ($self) = @_;
   $self->{app} = SDLx::App->new (
      title => "Blockminer3D 0.01alpha", width => $WIDTH, height => $HEIGHT, gl => 1);
   $self->{sdl_event} = SDL::Event->new;
   SDL::Video::GL_set_attribute (SDL::Constants::SDL_GL_SWAP_CONTROL, 1);
   SDL::Video::GL_set_attribute (SDL::Constants::SDL_GL_DOUBLEBUFFER, 1);

   glDepthFunc(GL_LESS);
   glEnable (GL_DEPTH_TEST);
   glMatrixMode (GL_PROJECTION);
   glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
   glEnable (GL_BLEND);
   glEnable (GL_CULL_FACE);
   glCullFace (GL_BACK);

   glHint (GL_PERSPECTIVE_CORRECTION_HINT, GL_FASTEST);
   glEnable (GL_TEXTURE_2D);
   glEnable (GL_FOG);
   glClearColor (0.5,0.5,0.5,1);
   glClearDepth (1.0);
   glShadeModel (GL_FLAT);

   glFogi (GL_FOG_MODE, GL_LINEAR);
   glFogfv_p (GL_FOG_COLOR, 0.5, 0.5, 0.5, 1);
   glFogf (GL_FOG_DENSITY, 0.35);
   glHint (GL_FOG_HINT, GL_DONT_CARE);
   glFogf (GL_FOG_START, 10);
   glFogf (GL_FOG_END,   20);

   glGenTextures_p(1);

   $self->load_texture ("res/blocks19.small.png", 1);
}

sub _get_texfmt {
   my ($surface) = @_;
   my $ncol = $surface->format->BytesPerPixel;
   my $rmsk = $surface->format->Rmask;
   warn "NCOL $ncol\n";
   ($ncol == 4 ? ($rmsk == 0x000000ff ? GL_RGBA : GL_BGRA)
               : ($rmsk == 0x000000ff ? GL_RGB  : GL_BGR))
}

sub load_texture {
   my ($self, $file, $nr) = @_;

   my ($name) = $file =~ /([^\/]+?)\.png/;

   my $img = SDL::Image::load ($file);
   die "Couldn't load texture: " . SDL::get_error () unless $img;
   SDL::Video::lock_surface ($img);

   my $texture_format = _get_texfmt ($img);

   glBindTexture (GL_TEXTURE_2D, $nr);
   glTexParameterf (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
   glTexParameterf (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

   gluBuild2DMipmaps_s (GL_TEXTURE_2D,
      $img->format->BytesPerPixel, $img->w, $img->h, $texture_format, GL_UNSIGNED_BYTE,
      ${$img->get_pixels_ptr});

   $self->{textures}->{$name} = $nr;
}

sub _render_quad {
   my ($x, $y, $z, $faces, $light) = @_;
   #d#warn "QUAD $x $y $z $light\n";

   #               0 front  1 top    2 back   3 left   4 right  5 bottom
   my @indices  = qw/0 1 2 3  1 5 6 2  7 6 5 4  4 5 1 0  3 2 6 7  3 7 4 0/;
   my @normals = (
      [ 0, 0,-1],
      [ 0, 1, 0],
      [ 0, 0, 1],
      [-1, 0, 0],
      [ 1, 0, 0],
      [ 0,-1, 0],
   ),
   my @vertices = (
      [ 0,  0,  0 ],
      [ 0,  1,  0 ],
      [ 1,  1,  0 ],
      [ 1,  0,  0 ],

      [ 0,  0,  1 ],
      [ 0,  1,  1 ],
      [ 1,  1,  1 ],
      [ 1,  0,  1 ],
   );

   my @uv = (
    #  w  h
      [1, 1],
      [1, 0],
      [0, 0],
      [0, 1],
   );

   foreach my $face (@$faces) {
      # glNormal3d (@{$normals[$face]}); # we dont use OpenGL lighting!

      foreach my $vertex (0..3) {
         my $index  = $indices[4 * $face + $vertex];
         my $coords = $vertices[$index];

         glColor3d ($light, $light, $light) if defined $light;
         glTexCoord2d(@{$uv[$vertex]});
         glVertex3d($coords->[0] + $x, $coords->[1] + $y, $coords->[2] + $z);
      }
   }
}

sub compile_chunk {
   my ($self, $cx, $cy, $cz) = @_;

   #d# warn "compiling... $cx, $cy, $cz\n";
   my $face_cnt;
   $self->{compiled_chunks}->{$cx}->{$cy}->{$cz} = OpenGL::List::glpList {
      glPushMatrix;
      glBegin (GL_QUADS);

      my $chnk = Games::Blockminer3D::Client::World::get_chunk ([$cx, $cy, $cz]);
      my @quads = map {
         [
            [
               $_->[0]->[0] + ($cx * $Games::Blockminer3D::Client::MapChunk::SIZE),
               $_->[0]->[1] + ($cy * $Games::Blockminer3D::Client::MapChunk::SIZE),
               $_->[0]->[2] + ($cz * $Games::Blockminer3D::Client::MapChunk::SIZE),
            ],
            $_->[1],
            $_->[2],
            $_->[3],
         ]
      } $chnk->visible_quads;
      #d# warn "[" . (scalar @quads) . "] quads\n";

      my $current_texture;

      # sort by texture name:
      for (sort { $a->[3] cmp $b->[3] } @quads) {
         my ($pos, $faces, $light, $tex) = @$_;
         my $tex_nr = 1; # FIXME: $self->{textures}->{$tex};
         if ($current_texture != $tex_nr) {
            glEnd;
            glBindTexture (GL_TEXTURE_2D, $tex_nr);
            glBegin (GL_QUADS);
            $current_texture = $tex_nr;
         }

         $face_cnt += scalar @$faces;

         _render_quad (@$pos, $faces, $light);
      }

      #for (my $x = 0; $x < $Games::Blockminer3D::Client::MapChunk::SIZE; $x++) {
      #   for (my $y = 0; $y < $Games::Blockminer3D::Client::MapChunk::SIZE; $y++) {
      #      for (my $z = 0; $z < $Games::Blockminer3D::Client::MapChunk::SIZE; $z++) {
      #         my $c = $chnk->[$x]->[$y]->[$z];
      #         if ($c->[2] && $c->[0] eq 'X') {
      #            _render_quad ($x, $y, $z, ((1 / 20) * $c->[1]) + 0.1);
      #         }
      #      }
      #   }
      #}

      glEnd;
      glPopMatrix;

   };
   #d# warn "faces: $face_cnt\n";
}

my $render_cnt;
my $render_time;
sub render_scene {
   my ($self) = @_;

   my $t1 = time;
   my $cc = $self->{compiled_chunks};
   my $pp =  $self->{phys_obj}->{player}->{pos};
   my ($chunk_pos) =
      vfloor (vsdiv ($pp, $Games::Blockminer3D::Client::MapChunk::SIZE));

   glClear (GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

   glMatrixMode(GL_PROJECTION);
   glLoadIdentity;
   gluPerspective (75, $WIDTH / $HEIGHT, 0.1, 20);

   glMatrixMode(GL_MODELVIEW);
   glLoadIdentity;
   # move and rotate the world:
   glRotatef ($self->{xrotate}, 1, 0, 0);
   glRotatef ($self->{yrotate}, 0, 1, 0);
   glTranslatef (@{vneg (vaddd ($pp, 0, 1.5, 0))});

   # coordinate system
   #d#glBindTexture (GL_TEXTURE_2D, 0);
   #d#glBegin (GL_LINES);
   #d#glColor3d (1, 0, 0);
   #d#glVertex3d(0, 0, 0);
   #d#glVertex3d(5, 0, 0);

   #d#glColor4d (0.2, 1, 0.2, 1);
   #d#glVertex3d(0, 0, 0);
   #d#glVertex3d(0, 5, 0);

   #d#glColor4d (0.2, 0.2, 1, 1);
   #d#glVertex3d(0, 0, 0);
   #d#glVertex3d(0, 0, 5);
   #d#glEnd;

   #d## center quad
   #d#glBindTexture (GL_TEXTURE_2D, 1);
   #d#glBegin (GL_QUADS);
   #d#_render_quad (0, 0, 0, 1);
   #d#glEnd;


   for my $dx (-1..1) { #-1..1) {
      for my $dy (-1..1) {
         for my $dz (-1..1) {
            my ($x, $y, $z) = (
               $chunk_pos->[0] + $dx,
               $chunk_pos->[1] + $dy,
               $chunk_pos->[2] + $dz
            );
            glCallList ($cc->{$x}->{$y}->{$z});
         }
      }
   }

   my $qp = [5, 5, 5];
   glPushMatrix;
   glBindTexture (GL_TEXTURE_2D, 0);
   glColor4d (1, 0, 0, 0.2);
   glTranslatef (9 - 0.1, 1 - 0.1, 9 - 0.1);
   glScalef (1.2, 1.2, 1.2);
   glBegin (GL_QUADS);
   _render_quad (0, 0, 0, [0..5]);
   glEnd;
   glPopMatrix;

   $render_time += time - $t1;
   $render_cnt++;
   $self->{app}->sync;
}

my $collide_cnt;
my $collide_time;
sub setup_event_poller {
   my ($self) = @_;

   my $sdle = $self->{sdl_event};
   my $ltime;

   my $accum_time = 0;
   my $dt = 1 / 40;

   my $fps;
   $self->{fps_w} = AE::timer 0, 5, sub {
      printf "%.5f FPS\n", $fps / 5;
      printf "%.5f secsPcoll\n", $collide_time / $collide_cnt if $collide_cnt;
      printf "%.5f secsPrender\n", $render_time / $render_cnt if $render_cnt;
      $collide_cnt = $collide_time = 0;
      $render_cnt = $render_time = 0;
      $fps = 0;
   };

   $self->{compile_w} = AE::timer 0, 0.1, sub {
      my $cc = $self->{compiled_chunks};
      my $pp = $self->{phys_obj}->{player}->{pos};
      #d# warn "compile at pos " . vstr ($pp) . "\n";
      my ($chunk_pos) =
         vfloor (vsdiv ($pp, $Games::Blockminer3D::Client::MapChunk::SIZE));

      for my $dx (0, -1, 1) {
         for my $dy (0, -1, 1) {
            for my $dz (0, -1, 1) {
               my ($x, $y, $z) = (@{vaddd ($chunk_pos, $dx, $dy, $dz)});
#              warn "check ($chunk_x $chunk_y $chunk_z) $x $y $z\n";
               unless ($cc->{$x}->{$y}->{$z}) {
                  $self->compile_chunk ($x, $y, $z);
                  warn "compiled $x, $y, $z\n";
                  return;
               }
            }
         }
      }
   };

   $self->{poll_input_w} = AE::timer 0, 0.03, sub {
      SDL::Events::pump_events();

      while (SDL::Events::poll_event($sdle)) {
         my $type = $sdle->type;
         my $key  = ($type == 2 || $type == 3) ? $sdle->key_sym : "";

         if ($type == 4) {
            $self->input_mouse_motion ($sdle->motion_x, $sdle->motion_y,
                                       $sdle->motion_xrel, $sdle->motion_yrel);

         } elsif ($type == 2) {
            $self->input_key_down ($key, SDL::Events::get_key_name ($key));

         } elsif ($type == 3) {
            $self->input_key_up ($key, SDL::Events::get_key_name ($key));

         } elsif ($type == 12) {
            warn "Exit event!\n";
            exit;
         } else {
            warn "unknown sdl type: $type\n";
         }
      }
   };

   $self->{poll_w} = AE::timer 0, 0.024, sub {
      $ltime = time - 0.02 if not defined $ltime;
      my $ctime = time;
      $accum_time += time - $ltime;
      $ltime = $ctime;

      while ($accum_time > $dt) {
         $self->physics_tick ($dt);
         $accum_time -= $dt;
      }

      if (delete $self->{change}) {
         warn "player status: pos: "
              . vstr ($self->{phys_obj}->{player}->{pos})
              . " rotx: $self->{xrotate}, roty: $self->{yrotate}\n";
      }

      $self->render_scene;
      $fps++;
      #}
   };
}

sub physics_tick : event_cb {
   my ($self, $dt) = @_;

 #  my $player = $self->{phys_obj}->{player};
 #  my $f = Games::Blockminer3D::Client::World::get_pos ($player->{pos}->array);
 #  warn "POS PLAYER $player->{pos}: ( @$f )\n";

   my $gforce = [0, -9.4, 0];

   my $player = $self->{phys_obj}->{player};

   viadd ($player->{vel}, vsmul ($gforce, $dt));
   #d#warn "DT: $dt => " .vstr( $player->{vel})."\n";

   if ((vlength ($player->{vel}) * $dt) > 0.3) {
      $player->{vel} = vsmul (vnorm ($player->{vel}), 0.28 / $dt);
   }
   viadd ($player->{pos}, vsmul ($player->{vel}, $dt));

   my $movement = [0, 0, 0];
   viadd ($movement, $self->{movement}->{straight})
      if defined $self->{movement}->{straight};
   viadd ($movement, $self->{movement}->{strafe})
      if defined $self->{movement}->{strafe};
   vismul ($movement, $dt);
   viadd ($player->{pos}, $movement);

  #d#warn "check player at $player->{pos}\n";
  #    my ($pos) = $chunk->collide ($player->{pos}, 0.3, \$collided);
  my $t1 = time;

  my $collided;
  my $collide_normal;
  #d#warn "check player pos " . vstr ($player->{pos}) . "\n";
  my ($pos) = Games::Blockminer3D::Client::World::collide_cylinder_aabb ($player->{pos}, 1.8, 0.3, \$collide_normal);
  #d#warn "new pos : ".vstr ($pos)." norm " . vstr ($collide_normal || []). "\n";
  $player->{pos} = $pos;
  $player->{vel} = [0, 0, 0] if $collide_normal;

  $collide_time += time - $t1;
  $collide_cnt++;

  #my ($pos) = Games::Blockminer3D::Client::World::collide (
  #   $player->{pos},
  #   0.3,
  #   \$collided);
  ##d#warn "collide $pos | $collided | vel $player->{vel}\n";
  #if ($collided) {
  #   #d# warn "Collided, new pos " . vstr ($pos) . " vector: " . vstr ($collided) . "\n";
  #   # TODO: specialcase upward velocity, they should not speed up on horiz. corners
  #   my $down_part;
  #   my $coll_depth = vlength ($collided);
  #   if ($coll_depth == 0) {
  #      #d#warn "collidedd vector == 0, set vel = 0\n";
  #      $down_part = 0;
  #   } else {
  #      vinorm ($collided, $coll_depth);
  #      my $vn = vnorm ($player->{vel});
  #      $down_part = 1 - abs (vdot ($collided, $vn));
  #      #d# warn "down part $cn . $vn => $down_part * $player->{vel}\n";
  #   }
  #   vismul ($player->{vel}, $down_part);
  #   $player->{pos} = $pos;
  ##    $player->{vel} = vector (0, 0, 0);
  #}
}

sub change_look_lock : event_cb {
   my ($self, $enabled) = @_;

   $self->{xrotate} = 0;
   $self->{yrotate} = 0;
   $self->{look_lock} = $enabled;

   if ($enabled) {
      $self->{app}->grab_input (SDL_GRAB_ON);
      SDL::Mouse::show_cursor (SDL_DISABLE);
   } else {
      $self->{app}->grab_input (SDL_GRAB_OFF);
      SDL::Mouse::show_cursor (SDL_ENABLE);
   }
}

sub input_key_up : event_cb {
   my ($self, $key, $name) = @_;

   if (grep { $name eq $_ } qw/s w/) {
      delete $self->{movement}->{straight};
   } elsif (grep { $name eq $_ } qw/a d/) {
      delete $self->{movement}->{strafe};
   } elsif ($name eq 'p') {
      my ($p) = vaddd ($self->{phys_obj}->{player}->{pos}, 0, -1, 0);
      my $bx = Games::Blockminer3D::Client::World::get_pos ($p);
      $bx->[0] = 'X';
      my $chnk = Games::Blockminer3D::Client::World::get_chunk ($p);
      $chnk->chunk_changed;
      $self->{compiled_chunks} = {};

   } elsif ($name eq 'l') {
      my ($p) = vaddd ($self->{phys_obj}->{player}->{pos}, 0, -1, 0);
      my $bx = Games::Blockminer3D::Client::World::get_pos ($p);
      $bx->[0] = ' ';
      my $chnk = Games::Blockminer3D::Client::World::get_chunk ($p);
      $chnk->chunk_changed;
      $self->{compiled_chunks} = {};
   } elsif ($name eq 't') {
      $self->{app}->fullscreen;

   } elsif ($name eq 'k') {
      $self->compile_scene;
   }

}
sub input_key_down : event_cb {
   my ($self, $key, $name) = @_;
   ($name eq "q" || $name eq 'escape') and exit;

   warn "Key down $key ($name)\n";

   my $move_x;

   #  -45    0     45
   #    \    |    /
   #-90 -         - 90
   #    /    |    \
   #-135 -180/180  135
   if ($name eq 'space') {
      viaddd ($self->{phys_obj}->{player}->{vel}, 0, 5, 0);
   } elsif ($name eq 'return') {
      viaddd ($self->{phys_obj}->{player}->{vel}, 0, -5, 0);
   } elsif ($name eq 'y') {
      viaddd ($self->{phys_obj}->{player}->{pos}, 0, -0.5, 0);
   } elsif ($name eq 'x') {
      viaddd ($self->{phys_obj}->{player}->{pos}, 0, 0.5, 0);
   } elsif ($name eq 'f') {
      $self->change_look_lock (not $self->{look_lock});
   } elsif (grep { $name eq $_ } qw/a s d w/) {
      my ($xdir, $ydir) = (
         $name eq 'w'        ?  2
         : ($name eq 's'     ? -2
                             :  0),
         $name eq 'a'        ? -2
         : ($name eq 'd'     ?  2
                             :  0),
      );

      my ($xd, $yd);
      if ($xdir) {
         $xd =  sin (deg2rad ($self->{yrotate}));# - 180));
         $yd = -cos (deg2rad ($self->{yrotate}));# - 180));
         $self->{movement}->{straight} = [($xd * $xdir), 0, ($yd * $xdir)];
      } else {
         $xdir = $ydir;
         $xd =  sin (deg2rad ($self->{yrotate} + 90));# - 180));
         $yd = -cos (deg2rad ($self->{yrotate} + 90));# - 180));
         $self->{movement}->{strafe} = [($xd * $xdir), 0, ($yd * $xdir)];
      }
   }
   $self->{change} = 1;
}

sub input_mouse_motion : event_cb {
   my ($self, $mx, $my, $xr, $yr) = @_;
   # FIXME: someone ought to fix relativ mouse positions... it's in twos complement here
   #        the SDL module has a bug => motion_yrel returns Uint16 and not Sint16.

   if ($self->{look_lock}) {
      my ($xc, $yc) = ($WIDTH / 2, $HEIGHT / 2);
      my ($xr, $yr) = (($mx - $xc), ($my - $yc));
      $self->{yrotate} += ($xr / $WIDTH) * 15;
      $self->{xrotate} += ($yr / $HEIGHT) * 15;
      $self->{xrotate} = Math::Trig::deg2deg ($self->{xrotate});
      $self->{yrotate} = Math::Trig::deg2deg ($self->{yrotate});
      $self->{change} = 1;
      #d# warn "rot ($xr,$yr) ($self->{xrotate},$self->{yrotate})\n";
      SDL::Mouse::warp_mouse ($xc, $yc);
   }
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

