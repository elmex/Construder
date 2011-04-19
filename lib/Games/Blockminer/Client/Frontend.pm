package Games::Blockminer::Client::Frontend;
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

use base qw/Object::Event/;

=head1 NAME

Games::Blockminer::Client::Frontend - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer::Client::Frontend->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;
   $self->init_app;
   $self->setup_event_poller;

   return $self
}

my ($WIDTH, $HEIGHT) = (600, 400);

sub set_chunk {
   my ($self, $world_x, $world_y, $chunk) = @_;
   warn "set chunk: $world_x $world_y $chunk\n";
   $self->{chunks}->[$world_x]->[$world_y] = $chunk;
   $self->compile_scene;
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
}

sub init_app {
   my ($self) = @_;
   $self->{app} = SDLx::App->new (
      title => "Blockminer 0.01alpha", width => $WIDTH, height => $HEIGHT, gl => 1);
   $self->{sdl_event} = SDL::Event->new;

   $self->{view_pos} = [0, 0, -20];

   glDepthFunc(GL_LESS);
   glEnable (GL_DEPTH_TEST);
   glMatrixMode(GL_PROJECTION);
   glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
   glEnable (GL_BLEND);
   glCullFace (GL_BACK);
   glEnable (GL_CULL_FACE);

   glHint (GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);
   glEnable (GL_TEXTURE_2D);
   glEnable (GL_FOG);
   glClearColor (0.5,0.5,0.5,1);
   glClearDepth (1.0);
   glShadeModel (GL_FLAT);

   glFogi (GL_FOG_MODE, GL_LINEAR);
   glFogfv_p (GL_FOG_COLOR, 0.5, 0.5, 0.5, 1);
   glFogf (GL_FOG_DENSITY, 0.35);
   glHint (GL_FOG_HINT, GL_DONT_CARE);
   glFogf (GL_FOG_START, 40);
   glFogf (GL_FOG_END,   80);

   glGenTextures_p(1);

   $self->load_texture ("res/filth.x11.32x32.png", 1);
}

sub _render_quad {
   my ($x, $y, $z, $light) = @_;
   #d#warn "QUAD $x $y $z $light\n";

   my @indices  = qw/4 5 6 7   1 2 6 5   0 1 5 4 0 3 2 1   0 4 7 3   2 3 7 6/;
   my @vertices = (
      [ -1, -1, -1 ],
      [ 1,  -1, -1 ],
      [ 1,  1,  -1 ],
      [ -1, 1,  -1 ],
      [ -1, -1, 1 ],
      [ 1,  -1, 1 ],
      [ 1,  1,  1 ],
      [ -1, 1,  1 ]);
   my @uv = (
      [1, 0],
      [0, 0],
      [0, 1],
      [1, 1],
   );


   foreach my $face ( 0 .. 5 ) {
      foreach my $vertex ( 0 .. 3 ) {
         my $index  = $indices[ 4 * $face + $vertex ];
         my $coords = $vertices[$index];

         glColor3d ($light, $light, $light);
         glTexCoord2d(@{$uv[$vertex]});
         glVertex3d($coords->[0] + $x, $coords->[1] + $y, $coords->[2] + $z);
      }
   }
}

sub compile_scene {
   my ($self) = @_;

   $self->{scene} = OpenGL::List::glpList {
      glPushMatrix;
      glBegin (GL_QUADS);

      my $chnk = $self->{chunks}->[0]->[0]->{map};
      warn "compile map: $chnk\n";
      for (my $x = 0; $x < $Games::Blockminer::Client::MapChunk::SIZE; $x++) {
         for (my $y = 0; $y < $Games::Blockminer::Client::MapChunk::SIZE; $y++) {
            for (my $z = 0; $z < $Games::Blockminer::Client::MapChunk::SIZE; $z++) {
               my $c = $chnk->[$x]->[$y]->[$z];
               if ($c->[0] eq 'X') {
                  _render_quad ($x * 2, $y * 2, $z * 2, ((1 / 20) * $c->[1]) + 0.1);
               }
            }
         }
      }

      glEnd;
      glPopMatrix;

   };
}

sub render_scene {
   my ($self) = @_;

   glClear (GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

   glMatrixMode(GL_PROJECTION);
   glLoadIdentity;
   gluPerspective (75, $WIDTH / $HEIGHT, 0.3, 60);

   glMatrixMode(GL_MODELVIEW);
   glLoadIdentity;
   glRotatef ($self->{xrotate}, 1, 0, 0);
   glRotatef ($self->{yrotate}, 0, 1, 0);
   glTranslatef (@{$self->{view_pos}});

   glCallList ($self->{scene});

   $self->{app}->sync;
}

sub setup_event_poller {
   my ($self) = @_;

   my $sdle = $self->{sdl_event};
   $self->{poll_w} = AE::timer 0, 0.005, sub {
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

 #     if (delete $self->{change}) {
         $self->render_scene;
 #     }
   };
}

sub change_look_lock : event_cb {
   my ($self, $enabled) = @_;

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
      $self->{view_pos}->[1] -= 1;
   } elsif ($name eq 'return') {
      $self->{view_pos}->[1] += 1;
   } elsif ($name eq 'f') {
      $self->change_look_lock (not $self->{look_lock});
   } elsif (grep { $name eq $_ } qw/a s d w/) {
      my ($xdir, $ydir) = (
         $name eq 'w'        ? -1
         : ($name eq 's'     ?  1
                             :  0),
         $name eq 'a'        ?  1
         : ($name eq 'd'     ? -1
                             :  0),
      );

      my ($xd, $yd);
      if ($xdir) {
         $xd =  sin (deg2rad ($self->{yrotate}));# - 180));
         $yd = -cos (deg2rad ($self->{yrotate}));# - 180));
      } else {
         $xdir = $ydir;
         $xd =  sin (deg2rad ($self->{yrotate} + 90));# - 180));
         $yd = -cos (deg2rad ($self->{yrotate} + 90));# - 180));
      }

      warn "MOVE " . rad2deg ($self->{yrotate}) . " | $xdir,$ydir | $xd,$yd\n";

      $self->{view_pos}->[2] += ($yd * $xdir) * 2.5;
      $self->{view_pos}->[0] += ($xd * $xdir) * 2.5;
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

