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
use Math::Trig qw/deg2rad rad2deg pi tan atan/;
use Time::HiRes qw/time/;
use POSIX qw/floor/;
use Games::Blockminer3D;
use Games::Blockminer3D::Vector;

use Games::Blockminer3D::Client::World;
use Games::Blockminer3D::Client::Resources;
use Games::Blockminer3D::Client::UI;
use Games::Blockminer3D::Client::Renderer;

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

my $PL_HEIGHT = 1;
my $PL_RAD    = 0.3;

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;
   $self->init_app;
   Games::Blockminer3D::Client::UI::init_ui;
   world_init;

#   world ()->reg_cb (chunk_changed => sub {
#      my ($w, $x, $y, $z, $force_render) = @_;
#      warn "killed chunk at $x $y $z\n";
#      if ($force_render)
#         {
#            $self->compile_chunk ($x, $y, $z);
#         }
#   });

   $self->init_physics;
   $self->setup_event_poller;
   $self->init_test;

   return $self
}

sub init_test {
   my ($self) = @_;
   $self->{active_uis}->{debug_hud} =
      Games::Blockminer3D::Client::UI->new (
         W => $WIDTH, H => $HEIGHT, res => $self->{res});
}

sub init_physics {
   my ($self) = @_;

   $self->{ghost_mode} = 1;

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
   glDisable (GL_DITHER);

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
}

#  0 front  1 top    2 back   3 left   4 right  5 bottom
my @indices  = (
   qw/ 0 1 2 3 /, # 0 front
   qw/ 1 5 6 2 /, # 1 top
   qw/ 7 6 5 4 /, # 2 back
   qw/ 4 5 1 0 /, # 3 left
   qw/ 3 2 6 7 /, # 4 right
   qw/ 3 7 4 0 /, # 5 bottom
);

#my @normals = (
#   [ 0, 0,-1],
#   [ 0, 1, 0],
#   [ 0, 0, 1],
#   [-1, 0, 0],
#   [ 1, 0, 0],
#   [ 0,-1, 0],
#),
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

sub _render_quad {
   my ($pos, $faces, $uv) = @_;
   #d#warn "QUAD $x $y $z $light\n";

   my @uv = (
    #  w  h
      [$uv->[2], $uv->[3]],
      [$uv->[2], $uv->[1]],
      [$uv->[0], $uv->[1]],
      [$uv->[0], $uv->[3]],
   );

   foreach (@$faces) {
      my ($face, $light) = @$_;
      glColor3f ($light, $light, $light) if defined $light;
      foreach my $vertex (0..3) {
         my $index  = $indices[4 * $face + $vertex];
         my $coords = $vertices[$index];

         glTexCoord2f (@{$uv[$vertex]});
         glVertex3f (
            $coords->[0] + $pos->[0],
            $coords->[1] + $pos->[1],
            $coords->[2] + $pos->[2]
         );
      }
   }
}

sub _render_highlight {
   my ($pos, $color, $rad) = @_;

   $rad ||= 0.08;
   $pos = vsubd ($pos, $rad, $rad, $rad);
   glPushMatrix;
   glBindTexture (GL_TEXTURE_2D, 0);
   glColor4f (@$color);
   glTranslatef (@$pos);
   glScalef (1 + 2*$rad, 1 + 2*$rad, 1+2*$rad);
   glBegin (GL_QUADS);
   _render_quad ([0, 0, 0], [map { [$_, undef] } 0..5]);
   glEnd;
   glPopMatrix;
}

sub build_chunk_arrays {
   my ($self) = @_;
   my @verts;

   for my $dx (0..$Games::Blockminer3D::Client::MapChunk::SIZE) {
      for my $dy (0..$Games::Blockminer3D::Client::MapChunk::SIZE) {
         for my $dz (0..$Games::Blockminer3D::Client::MapChunk::SIZE) {
            push @verts, [$dx, $dy, $dz];
         }
      }
   }
}

sub free_chunk {
   my ($self, $cx, $cy, $cz) = @_;
   my $l = delete $self->{compiled_chunks}->{$cx}->{$cy}->{$cz};
   glDeleteLists ($l, 1) if $l;
   warn "deleted chunk $cx, $cy, $cz\n";
}

sub compile_chunk {
   my ($self, $cx, $cy, $cz) = @_;

   warn "compiling... $cx, $cy, $cz.\n";

   $self->free_chunk ($cx, $cy, $cz);
   $self->{compiled_chunks}->{$cx}->{$cy}->{$cz} = OpenGL::List::glpList {
         my $compl;
      my (@vert, @color, @tex);
      Games::Blockminer3D::Renderer::chunk ($cx, $cy, $cz, \@vert, \@color, \@tex);
#d#     warn "VERTEXES: " . scalar (@vert) . " TEX: " . scalar (@tex) . "\n";
      $compl = [
         OpenGL::Array->new_list (GL_FLOAT, @vert),
         OpenGL::Array->new_list (GL_FLOAT, @color),
         OpenGL::Array->new_list (GL_FLOAT, @tex),
         scalar (@vert) / 12
      ];

      glPushMatrix;

      glTranslatef (
         $cx * $Games::Blockminer3D::Client::MapChunk::SIZE,
         $cy * $Games::Blockminer3D::Client::MapChunk::SIZE,
         $cz * $Games::Blockminer3D::Client::MapChunk::SIZE
      );

      render_quads ($compl);

      glPopMatrix;
   };
}

sub step_animations {
   my ($self, $dt) = @_;

   my @next_hl;
   for my $bl (@{$self->{box_highlights}}) {
      my ($pos, $color, $attr) = @$bl;

      if ($attr->{fading}) {
         if ($attr->{fading} > 0) {
            next if $color->[3] <= 0; # remove fade
            $color->[3] -= (1 / $attr->{fading}) * $dt;
         } else {
            next if $color->[3] >= 1; # remove fade
            $color->[3] += (1 / (-1 * $attr->{fading})) * $dt;
         }
      }

      push @next_hl, $bl;
   }
   $self->{box_highlights} = \@next_hl;
}

sub set_player_pos {
   my ($self, $pos) = @_;
   $self->{phys_obj}->{player}->{pos} = $pos;
}

sub is_player_chunk {
   my ($self, $cx, $cy, $cz) = @_;
   my ($pcx, $pcy, $pcz) = world_pos2chunk ($self->{phys_obj}->{player}->{pos});
   return $pcx == $cx && $pcy == $cy && $pcz == $cz;
}

sub update_chunk {
   my ($self, $cx, $cy, $cz) = @_;

   if (is_player_chunk ($cx, $cy, $cz)) {
      unshift @{$self->{chunk_update}}, [$cx, $cy, $cz];
   } else {
      push @{$self->{chunk_update}}, [$cx, $cy, $cz];
   }
}

sub add_highlight {
   my ($self, $pos, $color, $fade, $solid) = @_;

   push @$color, 0 if @$color < 4;

   #d# warn "HIGHLIGHt AT " .vstr ($pos) . " $fade > @$color > \n";

   $color->[3] = 1 if $fade > 0;
   push @{$self->{box_highlights}},
      [$pos, $color, { fading => $fade }];
# FIXME => move to server!
#   if ($solid) {
#      my $bx = world_get_box_at ($pos);
#      $bx->[0] = 1; # materialization!
#      world_change_chunk_at ($pos);
#   }
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
 #d#  glClear (GL_DEPTH_BUFFER_BIT);

   glMatrixMode(GL_PROJECTION);
   glLoadIdentity;
   gluPerspective (60, $WIDTH / $HEIGHT, 0.1, 20);

   glMatrixMode(GL_MODELVIEW);
   glLoadIdentity;
   glPushMatrix;

   # move and rotate the world:
   glRotatef ($self->{xrotate}, 1, 0, 0);
   glRotatef ($self->{yrotate}, 0, 1, 0);
   my $cpos;
   glTranslatef (@{vneg ($cpos = vaddd ($pp, 0, $PL_HEIGHT, 0))});

   my $t2 = time;
   my (@fcone) = $self->cam_cone;
   unshift @fcone, $cpos;
   my $culled = 0;
   #d# warn "FCONE ".vstr ($fcone[0]). ",".vstr ($fcone[1])." : $fcone[2]\n";
   my $t3 = time;

   for (world_visible_chunks_at ($pp)) {
      my ($cx, $cy, $cz) = @$_;
      my $pos = vsadd (vsmul ([$cx, $cy, $cz],
                       $Games::Blockminer3D::Client::MapChunk::SIZE),
                       $Games::Blockminer3D::Client::MapChunk::SIZE / 2);

      if (Games::Blockminer3D::Math::cone_sphere_intersect (
            @{$fcone[0]},
            @{$fcone[1]},
            $fcone[2],
            @$pos,
            $Games::Blockminer3D::Client::MapChunk::BSPHERE
      )) {
         my $compl = $cc->{$cx}->{$cy}->{$cz}
            or next;
         glCallList ($compl);
      } else {
         $culled++;
      }
   }
   if ($culled < 3) {
      warn "culled only $culled chunks in " . (time - $t2) . " secs!!!!";
   }

   for (@{$self->{box_highlights}}) {
      _render_highlight ($_->[0], $_->[1]);
   }

   my $qp = $self->{selected_box};
   _render_highlight ($qp, [1, 0, 0, 0.2], 0.04) if $qp;
   my $qpb = $self->{selected_build_box};
   _render_highlight ($qpb, [0, 0, 1, 0.05], 0.05) if $qp;

   glPopMatrix;

   $self->render_hud;

   $self->{app}->sync;

   $render_time += time - $t1;
   $render_cnt++;

}

sub render_hud {
   my ($self) = @_;

   #glDisable (GL_DEPTH_TEST);
   glClear (GL_DEPTH_BUFFER_BIT);

   glMatrixMode (GL_PROJECTION);
   glPushMatrix ();
   glLoadIdentity;
   glOrtho (0, $WIDTH, $HEIGHT, 0, -20, 20);

   glMatrixMode (GL_MODELVIEW);
   glPushMatrix ();
   glLoadIdentity;

   # this is the crosshair:
   my ($mw, $mh) = ($WIDTH / 2, $HEIGHT / 2);
   glPushMatrix;
   glTranslatef ($mw, $mh, 0);
   glColor4f (1, 1, 1, 0.3);
   glBindTexture (GL_TEXTURE_2D, 0);
   glBegin (GL_QUADS);

   #glTexCoord2d(1, 1);
   glVertex3f (-5, 5, -9.99);
   #glTexCoord2d(1, 0);
   glVertex3f (5, 5, -9.99);
   #glTexCoord2d(0, 1);
   glVertex3f (5, -5, -9.99);
   #glTexCoord2d(0, 0);
   glVertex3f (-5, -5, -9.99);

   glEnd ();
   glPopMatrix;

   #d# warn "ACTIVE UIS: " . join (', ', keys %{$self->{active_uis} || {}}) . "\n";

   $_->display for
      sort { $b->{prio} <=> $a->{prio} }
         values %{$self->{active_uis} || {}};

   glPopMatrix;
   glMatrixMode (GL_PROJECTION);
   glPopMatrix;

   #glEnable (GL_DEPTH_TEST);
   my $e;
   while (($e = glGetError ()) != GL_NO_ERROR) {
      warn "ERORR ".gluErrorString ($e)."\n";
      exit;
   }
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
      printf "%.5f secsPcoll\n", $collide_time / $collide_cnt if $collide_cnt;
      printf "%.5f secsPrender\n", $render_time / $render_cnt if $render_cnt;
      $self->{active_uis}->{debug_hud}->update ({
         window => {
            sticky => 1,
            extents => [left => up => 0.15, 0.05],
            color => "#000000",
            alpha => 0.8,
         },
         elements => [
            {
               type => 'text', extents => [0, 0, 1, 0.5],
               text => sprintf ("%.1f FPS\n", $fps / $fps_intv),
               color => "#ffff00",
               font => 'small'
            }
         ]
      });
      $collide_cnt = $collide_time = 0;
      $render_cnt = $render_time = 0;
      $fps = 0;
   };

   $self->{chunk_freeer} = AE::timer 0, 2, sub {
      my @vis_chunks = world_visible_chunks_at ($self->{phys_obj}->{player}->{pos});
      for my $kx (keys %{$self->{compiled_chunks}}) {
         for my $ky (keys %{$self->{compiled_chunks}->{$kx}}) {
            for my $kz (keys %{$self->{compiled_chunks}->{$kx}->{$ky}}) {
               unless (grep { $kx == $_->[0] && $ky == $_->[1] && $kz == $_->[2] } @vis_chunks) {
                  $self->free_chunk ($kx, $ky, $kz);
                  warn "freeed chunk $kx, $ky, $kz\n";
               }
            }
         }
      }
   };

   $self->{compile_w} = AE::timer 0, 0.028, sub {
      my $cc = $self->{compiled_chunks};
      my $pp = $self->{phys_obj}->{player}->{pos};
      #d# warn "compile at pos " . vstr ($pp) . "\n";
      # FIXME: vfloor is definitively NOT correct - probably :->
      while (@{$self->{chunk_update}}) {
         my $c = shift @{$self->{chunk_update}};
         $self->compile_chunk (@$c);
         return;
      }

      my (@chunks) = world_visible_chunks_at ($pp);
      my @fcone = $self->cam_cone;
      unshift @fcone,
         vaddd ($pp, 0, $PL_HEIGHT, 0);
      for (@chunks) {
         my ($cx, $cy, $cz) = @$_;
         my $pos = vsadd (vsmul ($_,
                          $Games::Blockminer3D::Client::MapChunk::SIZE),
                          $Games::Blockminer3D::Client::MapChunk::SIZE / 2);

         next unless
            Games::Blockminer3D::Math::cone_sphere_intersect (
               @{$fcone[0]}, @{$fcone[1]}, $fcone[2],
               @$pos, $Games::Blockminer3D::Client::MapChunk::BSPHERE);

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
   $self->{selector_w} = AE::timer 0, 0.1, sub {
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
   my $upd_pos = 0;
   $self->{poll_w} = AE::timer 0, 0.024, sub {
      $ltime = time - 0.02 if not defined $ltime;
      my $ctime = time;
      $accum_time += time - $ltime;
      $ltime = $ctime;

      while ($accum_time > $dt) {
         $self->physics_tick ($dt);
         $accum_time -= $dt;
      }

      if ($upd_pos++ > 5) {
         $self->update_player_pos ($self->{phys_obj}->{player}->{pos});
         $upd_pos = 0;
      }

      #d#if (delete $self->{change}) {
      #d#   warn "player status: pos: "
      #d#        . vstr ($self->{phys_obj}->{player}->{pos})
      #d#        . " rotx: $self->{xrotate}, roty: $self->{yrotate}\n";
      #d#}

      $self->render_scene;
      $fps++;
      #}
   };
}

sub calc_cam_cone {
   my ($nplane, $fplane, $fov, $w, $h, $lv) = @_;
   my $fdepth = ($h / 2) / tan (deg2rad ($fov) * 0.5);
   my $fcorn  = sqrt (($w / 2) ** 2 + ($h / 2) ** 2);
   my $ffov   = atan ($fcorn / $fdepth);
   (vnorm ($lv), $ffov);
}

sub cam_cone {
   my ($self) = @_;
   return @{$self->{cached_cam_cone}} if $self->{cached_cam_cone};
   $self->{cached_cam_cone} = [
      calc_cam_cone (0.1, 20, 60, $WIDTH, $HEIGHT, $self->get_look_vector)
   ];
   @{$self->{cached_cam_cone}}
}

sub get_look_vector {
   my ($self) = @_;
   return $self->{cached_look_vec} if $self->{cached_look_vec};

   my $xd =  sin (deg2rad ($self->{yrotate}));
   my $zd = -cos (deg2rad ($self->{yrotate}));
   my $yd =  cos (deg2rad ($self->{xrotate} + 90));
   my $yl =  sin (deg2rad ($self->{xrotate} + 90));
   $self->{cached_look_vec} = [$yl * $xd, $yd, $yl * $zd];

   delete $self->{cached_cam_cone};
   $self->cam_cone;

   return $self->{cached_look_vec};
}

sub get_selected_box_pos {
   my ($self) = @_;
   my $t1 = time;
   my $pp = $self->{phys_obj}->{player}->{pos};

   my $player_head = vaddd ($pp, 0, $PL_HEIGHT, 0);
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

            if (Games::Blockminer3D::World::is_solid_at (@$cur_box)) {
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

   my $player = $self->{phys_obj}->{player};

   my $bx = Games::Blockminer3D::World::at (@{vaddd ($player->{pos}, 0, -1, 0)});

   my $gforce = [0, -9.5, 0];
   if ($bx->[0] == 15) {
      $gforce = [0, 9.5, 0];
   }
   $gforce = [0,0,0] if $self->{ghost_mode};

   if ($self->{ghost_mode}) {
      $player->{vel} = [0, 0, 0];
   } else {
      viadd ($player->{vel}, vsmul ($gforce, $dt));
   }
   #d#warn "DT: $dt => " .vstr( $player->{vel})."\n";

   if ((vlength ($player->{vel}) * $dt) > $PL_RAD) {
      $player->{vel} = vsmul (vnorm ($player->{vel}), 0.28 / $dt);
   }
   viadd ($player->{pos}, vsmul ($player->{vel}, $dt));

   my $movement = _calc_movement (
      $self->{movement}->{straight}, $self->{movement}->{strafe},
      $self->{yrotate});
   $movement = vsmul ($movement, $self->{movement}->{speed} ? 2 : 1);
   viadd ($player->{pos}, vsmul ($movement, $dt));

   #d#warn "check player at $player->{pos}\n";
   #    my ($pos) = $chunk->collide ($player->{pos}, 0.3, \$collided);

   my $t1 = time;

   my $collide_normal;
   #d#warn "check player pos " . vstr ($player->{pos}) . "\n";

   my ($pos) =
      world_collide (
         $player->{pos},
         [
            [[0,0,0],$PL_RAD,-1],
            [[0, $PL_HEIGHT, 0], $PL_RAD,1]
         ],
         \$collide_normal);

   #d# warn "new pos : ".vstr ($pos)." norm " . vstr ($collide_normal || []). "\n";
   unless ($self->{ghost_mode}) {
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
   }

   $collide_time += time - $t1;
   $collide_cnt++;
}

sub change_look_lock : event_cb {
   my ($self, $enabled) = @_;

   $self->{xrotate} = 0;
   $self->{yrotate} = 0;
   $self->{look_lock} = $enabled;
   delete $self->{cached_look_vec};

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

   } elsif ($name eq 'left shift') {
      $self->{movement}->{speed} = 0;
   }

}

sub activate_ui {
   my ($self, $ui, $desc) = @_;

   my $obj = delete $self->{inactive_uis}->{$ui};

   $obj ||=
      Games::Blockminer3D::Client::UI->new (
         W => $WIDTH, H => $HEIGHT, res => $self->{res});
   $obj->update ($desc);
   $self->{active_uis}->{$ui} = $obj;
}

sub deactivate_ui {
   my ($self, $ui) = @_;
   $self->{inactive_uis}->{$ui} =
      delete $self->{active_uis}->{$ui};
}

sub input_key_down : event_cb {
   my ($self, $key, $name, $unicode) = @_;

   my $handled = 0;
   for (keys %{$self->{active_uis}}) {
      $self->{active_uis}->{$_}->input_key_press (
         $key, $name, chr ($unicode), \$handled);
      $self->deactivate_ui ($_) if $handled == 2;
      last if $handled;
   }
   return if $handled;

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
      viaddd ($self->{phys_obj}->{player}->{pos}, 0, -0.1, 0);
   } elsif ($name eq 'x') {
      viaddd ($self->{phys_obj}->{player}->{pos}, 0, 0.1, 0);
   } elsif ($name eq 'g') {
      $self->{ghost_mode} = not $self->{ghost_mode};
   } elsif ($name eq 'f') {
      $self->change_look_lock (not $self->{look_lock});
   } elsif ($name eq 'left shift') {
      $self->{movement}->{speed} = 1;

   } elsif (grep { $name eq $_ } qw/a s d w/) {
      my ($xdir, $ydir) = (
         $name eq 'w'        ?  2
         : ($name eq 's'     ? -2
                             :  0),
         $name eq 'a'        ? -2.5
         : ($name eq 'd'     ?  2.5
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
      delete $self->{cached_look_vec};
      $self->{change} = 1;
      #d# warn "rot ($xr,$yr) ($self->{xrotate},$self->{yrotate})\n";
      SDL::Mouse::warp_mouse ($xc, $yc);
   }
}

sub position_action : event_cb {
}

sub input_mouse_button : event_cb {
   my ($self, $btn, $down) = @_;
   warn "MASK $btn $down\n";
   return unless $down;

   my $sbp = $self->{selected_box};
   my $sbbp = $self->{selected_build_box};
   $self->position_action ($sbp, $sbbp, $btn);

   #d#if ($btn == 1) {
   #d#   my $sp = $self->{selected_build_box};
   #d#   return unless $sp;

   #d#   my $bx = world_get_box_at ($sp);
   #d#   $bx->[0] = 1;
   #d#   world_change_chunk_at ($sp);

   #d#} elsif ($btn == 3) {
   #d#   my $sp = $self->{selected_box};
   #d#   return unless $sp;

   #d#   my $bx = world_get_box_at ($sp);
   #d#   my $pt = $bx->[0];
   #d#   $bx->[0] = 0;
   #d#   world_change_chunk_at ($sp);
   #d#   warn "REMOVED OBJ $pt\n";

   #d#} elsif ($btn == 2) {
   #d#   my $sp = $self->{selected_box};
   #d#   return unless $sp;
   #d#   push @{$self->{box_highlights}},
   #d#      [[@$sp], [0, 1, 0, 0], { fading => 0.3 }];
   #d#}
}

sub update_player_pos : event_cb {
   my ($self, $pos) = @_;
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

