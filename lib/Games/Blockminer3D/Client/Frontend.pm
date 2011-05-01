package Games::Blockminer3D::Client::Frontend;
use common::sense;
use Carp;
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
use Games::Blockminer3D::Client::UI;

use base qw/Object::Event/;

=head1 NAME

Games::Blockminer3D::Client::Frontend - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Client::Frontend->new (%args)

=cut

my ($WIDTH, $HEIGHT) = (720, 400);#600, 400);

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;
   $self->init_app;
   Games::Blockminer3D::Client::UI::init_ui;
   world_init;

   world ()->reg_cb (chunk_changed => sub {
      my ($w, $x, $y, $z) = @_;
      warn "killed chunk at $x $y $z\n";
      $self->compile_chunk ($x, $y, $z);
   });

   $self->init_physics;
   $self->setup_event_poller;
   $self->init_test;

   return $self
}
sub init_test {
   my ($self) = @_;
   $self->{debug_hud} = Games::Blockminer3D::Client::UI->new (W => $WIDTH, H => $HEIGHT);
   $self->{query_ui} = Games::Blockminer3D::Client::UI->new (W => $WIDTH, H => $HEIGHT);
   $self->{query_ui}->update ({
         window => {
            pos => 'center',
            size => [$WIDTH - ($WIDTH / 5), 50],
            color => "#333333",
            alpha => 1,
         },
         elements => [
            {
               type => 'text', pos => [10, 10],
               size => [150, 38],
               text => "tes teste te eiwe iejfiwfjwei",
               color => "#0000ff",
               font => 'normal'
            },
         ]
   });
   delete $self->{query_ui};
}

sub init_physics {
   my ($self) = @_;

   $self->{phys_obj}->{player} = {
      pos => [5.5, 3.5, 5.5],#-25, -50, -25),
      vel => [0, 0, 0],
   };

   $self->{box_highlights} = [];
}

sub init_app {
   my ($self) = @_;
   $self->{app} = SDLx::App->new (
      title => "Blockminer3D 0.01alpha", width => $WIDTH, height => $HEIGHT, gl => 1);
   SDL::Events::enable_unicode (1);
   $self->{sdl_event} = SDL::Event->new;
   SDL::Video::GL_set_attribute (SDL::Constants::SDL_GL_SWAP_CONTROL, 1);
   SDL::Video::GL_set_attribute (SDL::Constants::SDL_GL_DOUBLEBUFFER, 1);

   glDepthFunc(GL_LESS);
   glEnable (GL_DEPTH_TEST);

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

 #  $self->load_texture ("res/blocks19.small.png", 1);
   $self->load_texture ("res/construction.jpg", 1);
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
   my ($pos, $faces, $light) = @_;
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
         glVertex3d(@{vadd ($coords, $pos)});
      }
   }
}

sub _render_highlight {
   my ($pos, $color, $rad) = @_;

   $rad ||= 0.05;
   $pos = vsubd ($pos, $rad, $rad, $rad);
   glPushMatrix;
   glBindTexture (GL_TEXTURE_2D, 0);
   glColor4d (@$color);
   glTranslatef (@$pos);
   glScalef (1 + 2*$rad, 1 + 2*$rad, 1+2*$rad);
   glBegin (GL_QUADS);
   _render_quad ([0, 0, 0], [0..5]);
   glEnd;
   glPopMatrix;
}

sub compile_chunk {
   my ($self, $cx, $cy, $cz) = @_;

   my $chnk = world_get_chunk ($cx, $cy, $cz)
      or return;
   warn "compiling... $cx, $cy, $cz: $chnk\n";
   my $face_cnt;
   $self->{compiled_chunks}->{$cx}->{$cy}->{$cz} = OpenGL::List::glpList {
      glPushMatrix;
      glBegin (GL_QUADS);

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

         _render_quad ($pos, $faces, $light);
      }

      glEnd;
      glPopMatrix;

   };
   #d# warn "faces: $face_cnt\n";
}

sub step_animations {
   my ($self, $dt) = @_;

   my @next_hl;
   for my $bl (@{$self->{box_highlights}}) {
      my ($pos, $color, $attr) = @$bl;

      if ($attr->{fading}) {
         next if $color->[3] >= 1; # remove fade
         $color->[3] += $attr->{fading} * $dt;
      }

      push @next_hl, $bl;
   }
   $self->{box_highlights} = \@next_hl;
}

my $render_cnt;
my $render_time;
sub render_scene {
   my ($self) = @_;

   my $t1 = time;
   my $cc = $self->{compiled_chunks};
   my $pp =  $self->{phys_obj}->{player}->{pos};
    #d#  warn "CHUNK " . vstr ($chunk_pos) . " from " . vstr ($pp) . "\n";

   glClear (GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

   glMatrixMode(GL_PROJECTION);
   glLoadIdentity;
   gluPerspective (60, $WIDTH / $HEIGHT, 0.1, 20);

   glMatrixMode(GL_MODELVIEW);
   glLoadIdentity;
   glPushMatrix;

   # move and rotate the world:
   glRotatef ($self->{xrotate}, 1, 0, 0);
   glRotatef ($self->{yrotate}, 0, 1, 0);
   glTranslatef (@{vneg (vaddd ($pp, 0, 1.3, 0))});

   for (world_visible_chunks_at ($pp)) {
      my ($cx, $cy, $cz) = @$_;
      my $compl = $cc->{$cx}->{$cy}->{$cz};
      glCallList ($compl) if $compl;
   }

   my $qp = $self->{selected_box};
   _render_highlight ($qp, [1, 0, 0, 0.2], 0.06) if $qp;
   my $qpb = $self->{selected_build_box};
   _render_highlight ($qpb, [0, 0, 1, 0.05], 0) if $qp;

   for (@{$self->{box_highlights}}) {
      _render_highlight ($_->[0], $_->[1]);
   }

   glPopMatrix;

   $self->render_hud;

   $self->{app}->sync;

   $render_time += time - $t1;
   $render_cnt++;
}

sub render_hud {
   my ($self) = @_;

   glDisable (GL_DEPTH_TEST);
   glDepthMask (GL_FALSE);

   glMatrixMode (GL_PROJECTION);
   glPushMatrix ();
   glLoadIdentity;
   glOrtho (0, $WIDTH, $HEIGHT, 0, -1, 1);

   glMatrixMode (GL_MODELVIEW);
   glPushMatrix ();
   glLoadIdentity;

   my ($mw, $mh) = ($WIDTH / 2, $HEIGHT / 2);
   glPushMatrix;
   glTranslatef ($mw, $mh, 0);
   glColor4d (1, 1, 1, 0.3);
   glBindTexture (GL_TEXTURE_2D, 0);
   glBegin (GL_QUADS);

   #glTexCoord2d(1, 1);
   glVertex3d (-5, 5, 0);
   #glTexCoord2d(1, 0);
   glVertex3d (5, 5, 0);
   #glTexCoord2d(0, 1);
   glVertex3d (5, -5, 0);
   #glTexCoord2d(0, 0);
   glVertex3d (-5, -5, 0);

   glEnd ();
   glPopMatrix;

   $self->{debug_hud}->display;
   $self->{query_ui}->display if $self->{query_ui};
 #  $self->{test_win}->display;

   glPopMatrix;
   glMatrixMode (GL_PROJECTION);
   glPopMatrix;

   glDepthMask (GL_TRUE);
   glEnable (GL_DEPTH_TEST);
}

my $collide_cnt;
my $collide_time;
sub setup_event_poller {
   my ($self) = @_;

   my $sdle = $self->{sdl_event};

   my $fps;
   my $fps_intv = 1;
   $self->{fps_w} = AE::timer 0, $fps_intv, sub {
      #printf "%.5f FPS\n", $fps / $fps_intv;
      #printf "%.5f secsPcoll\n", $collide_time / $collide_cnt if $collide_cnt;
      #printf "%.5f secsPrender\n", $render_time / $render_cnt if $render_cnt;
      $self->{debug_hud}->update ({
         window => {
            pos => 'up_left',
            size => [160, 30],
            color => "#0000ff",
            alpha => 0.80,
         },
         elements => [
            {
               type => 'text', pos => [2, 2],
               size => [150, 12],
               text => sprintf ("%.5f FPS\n", $fps / $fps_intv),
               color => "#ff0000",
               font => 'small'
            },
            {
               type => 'text', pos => [2, 14],
               size => [150, 12],
               text => sprintf ("POS %6.3f %6.3f %6.3f\n",
                                @{$self->{phys_obj}->{player}->{pos}}),
               color => "#00ff00",
               font => 'small'
            },

         ]
      });
      $collide_cnt = $collide_time = 0;
      $render_cnt = $render_time = 0;
      $fps = 0;
   };

   $self->{compile_w} = AE::timer 0, 0.1, sub {
      my $cc = $self->{compiled_chunks};
      my $pp = $self->{phys_obj}->{player}->{pos};
      #d# warn "compile at pos " . vstr ($pp) . "\n";
      # FIXME: vfloor is definitively NOT correct - probably :->
      my (@chunks) = world_visible_chunks_at ($pp);
      for (@chunks) {
         my ($cx, $cy, $cz) = @$_;
         unless ($cc->{$cx}->{$cy}->{$cz}) {
            $self->compile_chunk ($cx, $cy, $cz);
            if ($cc->{$cx}->{$cy}->{$cz}) {
               warn "compiled $cx, $cy, $cz\n";
               return;
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
            $self->input_key_down ($key, SDL::Events::get_key_name ($key), $sdle->key_unicode);

         } elsif ($type == 3) {
            $self->input_key_up ($key, SDL::Events::get_key_name ($key));

         } elsif ($type == SDL_MOUSEBUTTONUP) {
            $self->input_mouse_button ($sdle->button_button, 0);

         } elsif ($type == SDL_MOUSEBUTTONDOWN) {
            $self->input_mouse_button ($sdle->button_button, 1);

         } elsif ($type == 12) {
            warn "Exit event!\n";
            exit;
         } else {
            warn "unknown sdl type: $type\n";
         }
      }
   };

   my $anim_ltime;
   my $anim_dt = 1 / 25;
   my $anim_accum_time = 0;
   $self->{selector_w} = AE::timer 0, 0.04, sub {
      ($self->{selected_box}, $self->{selected_build_box})
         = $self->get_selected_box_pos;

      $anim_ltime = time - 0.02 if not defined $anim_ltime;
      my $ctime = time;
      $anim_accum_time += time - $anim_ltime;
      $anim_ltime = $ctime;

      while ($anim_accum_time > $anim_dt) {
         $self->step_animations ($anim_dt);
         $anim_accum_time -= $anim_dt;
      }

   };

   my $ltime;
   my $accum_time = 0;
   my $dt = 1 / 40;
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

sub get_look_vector {
   my ($self) = @_;

   my $xd =  sin (deg2rad ($self->{yrotate}));
   my $zd = -cos (deg2rad ($self->{yrotate}));
   my $yd =  cos (deg2rad ($self->{xrotate} + 90));
   my $yl =  sin (deg2rad ($self->{xrotate} + 90));
   return [$yl * $xd, $yd, $yl * $zd];
}

sub get_selected_box_pos {
   my ($self) = @_;
   my $t1 = time;
   my $pp = $self->{phys_obj}->{player}->{pos};

   my $player_head = vaddd ($pp, 0, 1.3, 0);
   my $foot_box    = vfloor ($pp);
   my $head_box    = vfloor ($player_head);
   my $rayd        = $self->get_look_vector;

   my ($select_pos);

   my $min_dist = 9999;
   for my $dx (-2..2) {
      for my $dy (-3..2) { # floor and above head?!
         for my $dz (-2..2) {
            # now skip the player boxes
            my $cur_box = vaddd ($head_box, $dx, $dy, $dz);
            #d# next unless $dx == 0 && $dz == 0 && $cur_box->[1] == $foot_box->[1] - 1;
            next if $dx == 0 && $dz == 0
                    && grep { $cur_box->[1] == $_ }
                          $foot_box->[1]..$head_box->[1];

            my $b = world_get_box_at ($cur_box);
            if (world_is_solid_box ($b)) {
               my ($dist, $q) =
                  world_intersect_ray_box (
                     $player_head, $rayd, $cur_box);
               #d#warn "BOX AT " . vstr ($cur_box) . " ".vstr ($rayd)." from "
               #d#               . vstr ($player_head) . "DIST $dist at " . vstr ($q) . "\n";
               if ($dist > 0 && $min_dist > $dist) {
                  $min_dist   = $dist;
                  $select_pos = $cur_box;
               }
            }
         }
      }
   }

   my $build_box;
   if ($select_pos) {
      my $box_center    = vaddd ($select_pos, 0.5, 0.5, 0.5);
      my $intersect_pos = vadd ($player_head, vsmul ($rayd, $min_dist));
      my $norm_dir = vsub ($intersect_pos, $box_center);

      my $max_coord;
      my $cv = 0;
      for (0..2) {
         if (abs ($cv) < abs ($norm_dir->[$_])) {
            $cv = $norm_dir->[$_];
            $max_coord = $_;
         }
      }
      my $norm = [0, 0, 0];
      $norm->[$max_coord] = $cv < 0 ? -1 : 1;
      #d# warn "Normal direction: " . vstr ($nn) . ", ". vstr ($norm) . "\n";

      $build_box = vfloor (vadd ($box_center, $norm));
      if (grep {
               $foot_box->[0] == $build_box->[0]
            && $_ == $build_box->[1]
            && $foot_box->[2] == $build_box->[2]
          } $foot_box->[1]..$head_box->[1]
      ) {
         $build_box = undef;
      }
   }


   #d# warn sprintf "%.5f selection\n", time - $t1;

   ($select_pos, $build_box)
}

sub _calc_movement {
   my ($forw_speed, $side_speed, $rot) = @_;
   my $xd =  sin (deg2rad ($rot));# - 180));
   my $yd = -cos (deg2rad ($rot));# - 180));
   my $forw = vsmul ([$xd, 0, $yd], $forw_speed);

   $xd =  sin (deg2rad ($rot + 90));# - 180));
   $yd = -cos (deg2rad ($rot + 90));# - 180));
   viadd ($forw, vsmul ([$xd, 0, $yd], $side_speed));
   $forw
}


sub physics_tick : event_cb {
   my ($self, $dt) = @_;

 #  my $player = $self->{phys_obj}->{player};
 #  my $f = world_get_pos ($player->{pos}->array);
 #  warn "POS PLAYER $player->{pos}: ( @$f )\n";

   my $gforce = [0, -9.4, 0];

   my $player = $self->{phys_obj}->{player};

   viadd ($player->{vel}, vsmul ($gforce, $dt));
   #d#warn "DT: $dt => " .vstr( $player->{vel})."\n";

   if ((vlength ($player->{vel}) * $dt) > 0.3) {
      $player->{vel} = vsmul (vnorm ($player->{vel}), 0.28 / $dt);
   }
   viadd ($player->{pos}, vsmul ($player->{vel}, $dt));

   my $movement = _calc_movement (
      $self->{movement}->{straight}, $self->{movement}->{strafe},
      $self->{yrotate});
   viadd ($player->{pos}, vsmul ($movement, $dt));

   #d#warn "check player at $player->{pos}\n";
   #    my ($pos) = $chunk->collide ($player->{pos}, 0.3, \$collided);

   my $t1 = time;

   my $collide_normal;
   #d#warn "check player pos " . vstr ($player->{pos}) . "\n";

   my ($pos) =
      world_collide_cylinder_aabb (
         $player->{pos}, 1.5, 0.3, \$collide_normal);

   #d#warn "new pos : ".vstr ($pos)." norm " . vstr ($collide_normal || []). "\n";
   $player->{pos} = $pos;

   if ($collide_normal) {
       # figure out how much downward velocity is removed:
       my $down_part;
       my $coll_depth = vlength ($collide_normal);
       if ($coll_depth == 0) {
          #d#warn "collidedd vector == 0, set vel = 0\n";
          $down_part = 0;

       } else {
          vinorm ($collide_normal, $coll_depth);

          my $vn = vnorm ($player->{vel});
          $down_part = 1 - abs (vdot ($collide_normal, $vn));
          #d# warn "down part $cn . $vn => $down_part * $player->{vel}\n";
       }
       #d# warn "downpart $down_part\n";
       vismul ($player->{vel}, $down_part);
   }

   $collide_time += time - $t1;
   $collide_cnt++;
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

   } elsif ($name eq 't') {
      $self->{app}->fullscreen;
   }

}
sub input_key_down : event_cb {
   my ($self, $key, $name, $unicode) = @_;

   if ($self->{query_ui}) {
      $self->{query_ui}->input_key_press ($key, $name, chr ($unicode));
 #     return;
   }

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
         $name eq 'w'        ?  3
         : ($name eq 's'     ? -3
                             :  0),
         $name eq 'a'        ? -4
         : ($name eq 'd'     ?  4
                             :  0),
      );

      my ($xd, $yd);
      if ($xdir) {
         $self->{movement}->{straight} = $xdir;
      } else {
         $self->{movement}->{strafe} = $ydir;
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
      $self->{xrotate} = -90 if $self->{xrotate} < -90;
      $self->{xrotate} = 90 if $self->{xrotate} > 90;
      $self->{yrotate} = Math::Trig::deg2deg ($self->{yrotate});
      $self->{change} = 1;
      #d# warn "rot ($xr,$yr) ($self->{xrotate},$self->{yrotate})\n";
      SDL::Mouse::warp_mouse ($xc, $yc);
   }
}

sub input_mouse_button : event_cb {
   my ($self, $btn, $down) = @_;
   warn "MASK $btn $down\n";
   return unless $down;
   if ($btn == 1) {
      my $sp = $self->{selected_build_box};
      return unless $sp;

      my $bx = world_get_box_at ($sp);
      $bx->[0] = 'X';
      world_change_chunk_at ($sp);

   } elsif ($btn == 3) {
      my $sp = $self->{selected_box};
      return unless $sp;

      my $bx = world_get_box_at ($sp);
      $bx->[0] = ' ';
      world_change_chunk_at ($sp);

   } elsif ($btn == 2) {
      my $sp = $self->{selected_box};
      return unless $sp;
      push @{$self->{box_highlights}},
         [[@$sp], [0, 1, 0, 0], { fading => 0.3 }];
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

