# Games::Construder - A 3D Game written in Perl with an infinite and modifiable world.
# Copyright (C) 2011  Robin Redeker
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
package Games::Construder::Client::Frontend;
use common::sense;
use Carp;
use SDL;
use SDLx::App;
use SDL::Mouse;
use SDL::Video;
use SDL::Events;
use SDLx::Sound;
use SDL::Image;
use SDL::Event;
use OpenGL qw(:all);
use OpenGL::List;
use AnyEvent;
use Math::Trig qw/deg2rad rad2deg pi tan atan/;
use Time::HiRes qw/time/;
use POSIX qw/floor/;
use Games::Construder;
use Games::Construder::Vector;

use Games::Construder::Client::World;
use Games::Construder::Client::Resources;
use Games::Construder::UI;
use Games::Construder::Client::UI;
use Games::Construder::Logging;

use base qw/Object::Event/;

=head1 NAME

Games::Construder::Client::Frontend - Client Rendering, Physics, Keyboard handling and UI management

=over 4

=cut

my ($WIDTH, $HEIGHT) = (800, 600);
my $DEPTH = 24;
my $UPDATE_P_FRAME = 25;

my $PL_HEIGHT  = 1.3;
my $PL_RAD     = 0.3;
my $PL_VIS_RAD = 3;
my $FAR_PLANE  = 26;
my $FOG_DEFAULT = "Darkness";
my %FOGS = (
   Darkness    => [0, 0, 0, 1],
   Athmosphere => [0.45, 0.45, 0.65, 1],
);

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;
   $self->init_app;
   Games::Construder::Renderer::init ();
   Games::Construder::Client::UI::init_ui;
   world_init;

   $self->init_physics;
   $self->setup_event_poller;


   return $self
}

sub init_physics {
   my ($self) = @_;

   $self->{ghost_mode} = 0;

   $self->{phys_obj}->{player} = {
      pos => [5.5, 3.5, 5.5],#-25, -50, -25),
      vel => [0, 0, 0],
   };

   $self->{box_highlights} = [];
}

sub exit_app {
   my ($self) = @_;
   exit;
}

sub resize_app {
   my ($self, $nw, $nh) = @_;

   $self->{res}->desetup_textures;
   $self->unload_geoms;

   for (values %{$self->{active_uis}}) {
      $_->pre_resize_screen ($nw, $nh);
   }
   for (values %{$self->{inactive_uis}}) {
      $_->pre_resize_screen ($nw, $nh);
   }

   eval {
      $self->{app}->resize ($nw, $nh);
   };
   if ($@) {
      $self->msg ("Can't resize application: $@");
   }

   ($WIDTH, $HEIGHT) = ($nw, $nh);

   $self->init_gl;

   $self->{res}->setup_textures;

   for (values %{$self->{active_uis}}) {
      $_->resize_screen ($nw, $nh);
      $_->update;
   }
   for (values %{$self->{inactive_uis}}) {
      $_->resize_screen ($nw, $nh);
   }

   $self->all_chunks_dirty;

   delete $self->{cached_cam_cone};
   $self->calc_visibility;
}

sub init_app {
   my ($self) = @_;
   $self->{app} = SDLx::App->new (
      title  => "Construder 0.01alpha",
      width  => $WIDTH,
      height => $HEIGHT,
      d      => $DEPTH,
      gl     => 1,
      resizeable => 1
   );

   #d# my $init = SDL::Mixer::init (SDL::Mixer::MIX_INIT_OGG);
   #d# unless ($init & SDL::Mixer::MIX_INIT_OGG) {
   #d#    die "Couldn't initialize SDL Mixer for OGG!\n";
   #d# }

   #d# SDL::Mixer::open_audio( 44100, SDL::Mixer::AUDIO_S16SYS, 2, 4096 );
   #d# SDL::Mixer::Music::volume_music ($self->{res}->{config}->{volume_music});

   $self->set_ambient_light ($self->{res}->{config}->{ambient_light});

   SDL::Events::enable_unicode (1);
   $self->{sdl_event} = SDL::Event->new;
   SDL::Video::GL_set_attribute (SDL::Constants::SDL_GL_SWAP_CONTROL, 1);
   SDL::Video::GL_set_attribute (SDL::Constants::SDL_GL_DOUBLEBUFFER, 1);

   $self->init_gl;
}

sub init_gl {
   my ($self) = @_;

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
   glClearDepth (1.0);
   glShadeModel (GL_FLAT);

   glFogi (GL_FOG_MODE, GL_LINEAR);
   glFogf (GL_FOG_DENSITY, 0.45);
   glHint (GL_FOG_HINT, GL_FASTEST);

   $self->visibility_radius ($PL_VIS_RAD);
   $self->update_fog;

   glViewport (0, 0, $WIDTH, $HEIGHT);
}

sub fog {
   my ($self) = @_;
   $self->{res}->{config}->{fog} eq ''
      ? $FOG_DEFAULT
      : $self->{res}->{config}->{fog}
}

sub update_fog {
   my ($self) = @_;
   my $fog = $FOGS{$self->fog ()} || $FOGS{$FOG_DEFAULT};
   glClearColor (@$fog);
   glFogfv_p (GL_FOG_COLOR, @$fog);
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
   my ($pos, $scale) = @_;

   $scale ||= 1;

   for my $face (0..5) {
      for my $vertex (0..3) {
         my $index  = $indices[4 * $face + $vertex];
         my $coords = $vertices[$index];

         glVertex3f (
            ($coords->[0] * $scale) + $pos->[0],
            ($coords->[1] * $scale) + $pos->[1],
            ($coords->[2] * $scale) + $pos->[2]
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
   _render_quad ([0, 0, 0]);
   glEnd;
   glPopMatrix;
}

sub set_ambient_light {
   my ($self, $l) = @_;
   Games::Construder::Renderer::set_ambient_light ($l);
   $self->all_chunks_dirty;
}

sub all_chunks_dirty {
   my ($self) = @_;
   for my $id (keys %{$self->{compiled_chunks}}) {
      $self->{dirty_chunks}->{$id} = 1;
   }
}

sub free_compiled_chunk {
   my ($self, $cx, $cy, $cz) = @_;
   my $c = [$cx, $cy, $cz];
   my $id = world_pos2id ($c);
   my $l = delete $self->{compiled_chunks}->{$id};
   Games::Construder::Renderer::free_geom ($l) if $l;
   # WARNING FIXME XXX: this might not free up all chunks that were set/initialized by the server!
   Games::Construder::World::purge_chunk (@$c);
}

sub unload_geoms {
   my ($self) = @_;

   for (keys %{$self->{compiled_chunks}}) {
      my $geom = delete $self->{compiled_chunks}->{$_};
      Games::Construder::Renderer::free_geom ($geom);
   }
}

sub compile_chunk {
   my ($self, $cx, $cy, $cz) = @_;
   my $id = world_pos2id ([$cx, $cy, $cz]);

   #d# warn "compiling... $cx, $cy, $cz.\n";
   my $geom = $self->{compiled_chunks}->{$id};

   unless ($geom) {
      $geom = $self->{compiled_chunks}->{$id} =
         Games::Construder::Renderer::new_geom ();
   }

   delete $self->{dirty_chunks}->{$id};
   return Games::Construder::Renderer::chunk ($cx, $cy, $cz, $geom);
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
   warn "NEW PLAYER POS: @$pos\n";
   $self->{phys_obj}->{player}->{pos} = $pos;
   delete $self->{visible_chunks};
   $self->calc_visibility;
}

sub set_other_poses {
   my ($self, $poses) = @_;
   $self->{other_players} = @$poses;
}

sub get_visible_chunks {
   my ($self) = @_;
   Games::Construder::Util::visible_chunks_at (
      $self->{phys_obj}->{player}->{pos}, $PL_VIS_RAD);
}

# currently used to determine which chunks to keep cached:
sub can_see_chunk {
   my ($self, $cx, $cy, $cz, $range_fact) = @_;
   my $plc = [world_pos2chunk ($self->{phys_obj}->{player}->{pos})];
   vlength (vsub ([$cx, $cy, $cz], $plc)) < $PL_VIS_RAD * ($range_fact || 1);
}

sub dirty_chunk {
   my ($self, $chnk) = @_;
   my $id = world_pos2id ($chnk);
   $self->{dirty_chunks}->{$id} = $chnk;
}

sub clear_chunk {
   my ($self, $chnk) = @_;
   $self->free_compiled_chunk (@$chnk);
}

sub remove_highlight_model {
   my ($self, $id) = @_;
   delete $self->{model_highlights}->{$id};
}

sub add_highlight_model {
   my ($self, $pos, $relposes, $id) = @_;
# FIXME: might need to be rebuilt on init_gl()! (resizes!)
   $self->{model_highlights}->{$id} = OpenGL::List::glpList {
      glPushMatrix;
      glBindTexture (GL_TEXTURE_2D, 0);
      glTranslatef (@$pos);
      for (@$relposes) {
         my ($p, $c) = @$_;
         $p = vaddd ($p, 0.3, 0.3, 0.3);
         glColor4f (@{@$c > 3 ? $c : [@$c, 0.5]});
         glBegin (GL_QUADS);
         _render_quad ($p, 0.3);
         glEnd;
      }
      glPopMatrix;
   };
}

sub add_highlight {
   my ($self, $pos, $color, $fade, $id) = @_;

   push @$color, 0 if @$color < 4;

   #d# warn "HIGHLIGHt AT " .vstr ($pos) . " $fade > @$color > \n";

   $color->[3] = 1 if $fade > 0;
   push @{$self->{box_highlights}},
      [$pos, $color, { fading => $fade, rad => 0.08 + rand (0.005) }, $id];
}

my $old_pp;

sub calc_visibility {
   my ($self) = @_;

   my $play_pos = $self->{phys_obj}->{player}->{pos};
   my $ppf = vfloor ($play_pos);
   return unless
      !$self->{cached_cam_cone}
      || $ppf->[0] != $old_pp->[0]
      || $ppf->[1] != $old_pp->[1]
      || $ppf->[2] != $old_pp->[2];
   $old_pp = $ppf;

   my $cam_pos  = vaddd ($play_pos, 0, $PL_HEIGHT, 0);
   my (@fcone) = $self->cam_cone;
   unshift @fcone, $cam_pos;

   my $vis_chunks =
      Games::Construder::Math::calc_visible_chunks_at_in_cone (
         @$play_pos, $PL_VIS_RAD,
         @{$fcone[0]}, @{$fcone[1]}, $fcone[2],
         $Games::Construder::Client::World::BSPHERE);

   my @chunks;
   my $plchnk = [world_pos2chunk ($ppf)];
   for my $x (-1,0,1) {
      for my $y (-1,0,1) {
         for my $z (-1,0,1) {
            my $c = vaddd ($plchnk, $x, $y, $z);
            push @chunks, $c;
         }
      }
   }

   while (@$vis_chunks) {
      push @chunks, [shift @$vis_chunks, shift @$vis_chunks, shift @$vis_chunks];
   }

   my $old_vis = $self->{visible_chunks};
   my $new_vis = { };
   my (@newv, @oldv, @req);
   for my $c (@chunks) {
      my $cid = world_pos2id ($c);
      if ($old_vis->{$cid}) {
         delete $old_vis->{$cid};

      } elsif (not exists $new_vis->{$cid}) {
         push @newv, $c;
      }
      $new_vis->{$cid} = $c;
      unless (Games::Construder::World::has_chunk (@$c)) {
         push @req, $c;
      }
   }
 #d#  print "VISIBLE CHUNKS: " . join (", ", keys %$new_vis) . " (NEW ".join (", ", map { world_pos2id ($_) } @newv).") (OLD "  . join (", ", map { world_pos2id ($_) } @oldv).")\n";
   (@oldv) = values %$old_vis;
   $self->visible_chunks_changed (\@newv, \@oldv, \@req)
      if @newv || @oldv || @req;
   $self->{visible_chunks} = $new_vis;
}

my $render_cnt;
my $render_time;
sub render_scene {
   my ($self, $frame_time) = @_;

   my $t1 = time;
   my $cc = $self->{compiled_chunks};
   my $pp =  $self->{phys_obj}->{player}->{pos};
    #d#  warn "CHUNK " . vstr ($chunk_pos) . " from " . vstr ($pp) . "\n";

   glClear (GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
 #d#  glClear (GL_DEPTH_BUFFER_BIT);

   glMatrixMode(GL_PROJECTION);
   glLoadIdentity;
   gluPerspective (72, $WIDTH / $HEIGHT, 0.1, $FAR_PLANE);

   glMatrixMode(GL_MODELVIEW);
   glLoadIdentity;
   glPushMatrix;

   # move and rotate the world:
   glRotatef ($self->{xrotate}, 1, 0, 0);
   glRotatef ($self->{yrotate}, 0, 1, 0);
   my $cpos;
   glTranslatef (@{vneg ($cpos = vaddd ($pp, 0, $PL_HEIGHT, 0))});

   my ($txtid) = $self->{res}->obj2texture (1);
   glBindTexture (GL_TEXTURE_2D, $txtid);

   #d# warn "FCONE ".vstr ($fcone[0]). ",".vstr ($fcone[1])." : $fcone[2]\n";

   my @compl_end; # are to be compiled at the end of the frame
   for my $id (keys %{$self->{visible_chunks}}) {
      if (!$cc->{$id} || $self->{dirty_chunks}->{$id}) {
         push @compl_end, $self->{visible_chunks}->{$id};
      }
      my $compl = $cc->{$id}
         or next;
      Games::Construder::Renderer::draw_geom ($compl);
   }

   for (@{$self->{box_highlights}}) {
      _render_highlight ($_->[0], $_->[1], $_->[2]->{rad});
   }

   for (values %{$self->{model_highlights}}) {
      glCallList ($_);
   }

   my $qp = $self->{selected_box};
   _render_highlight ($qp, [1, 0, 0, 0.2], 0.04) if $qp;

   glPopMatrix;

   $self->render_hud;

   #glFinish; # what for?

   $self->{app}->sync;

   my $tleft = $frame_time - (time - $t1);

   if (@compl_end) {
      my $plchnk = world_pos2chunk ($pp);
      (@compl_end) = sort {
         vlength (vsub ($plchnk, $a))
         <=>
         vlength (vsub ($plchnk, $b))
      } @compl_end;
      my $tc = time;
      $tleft -= $tleft / 4; # lets don't overdo it
      # we MUST allow at least one per frame, otherwise on
      # other machines maybe none are compiled...
      my $ac = $tleft < 0 ? 0.001 : $tleft;

      my @request;

      my $cnt = 0;
      my $max = 9;
      while ($max-- > 0 && (time - $tc) < $ac) {
         my $chnk = shift @compl_end
            or last;
         unless ($self->compile_chunk (@$chnk)) {
            push @request, $chnk;
         }
         $cnt++;
      }
      my $tok = time - $tc;

      if ($tok > $tleft) {
         ctr_log (debug =>
            "compiled $cnt chunks in $tok, but only had $tleft ($ac) left, but "
            . scalar (@compl_end) . " chunks still to compile...");
      }

      (@compl_end) = ();

      if (@request) {
         ctr_log (debug => "requesting %d chnks", scalar (@request));
         $self->visible_chunks_changed ([], [], \@request);
      }
   }

   $render_time += time - $t1;
   $render_cnt++;
}

sub render_hud {
   my ($self) = @_;

   #glDisable (GL_DEPTH_TEST);
   glDisable (GL_FOG);
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

   glVertex3f (-5,  5, -9.99);
   glVertex3f ( 5,  5, -9.99);
   glVertex3f ( 5, -5, -9.99);
   glVertex3f (-5, -5, -9.99);

   glEnd ();
   glPopMatrix;

   #d# warn "ACTIVE UIS: " . join (', ', keys %{$self->{active_uis} || {}}) . "\n";

   for (values %{$self->{active_uis}}) {
      next unless $_->{sticky};
      $_->display;
   }

   if (@{$self->{active_ui_stack}}) {
      $self->{active_ui_stack}->[-1]->[1]->display;
   }

   glPopMatrix;
   glMatrixMode (GL_PROJECTION);
   glPopMatrix;

   glEnable (GL_FOG);

   #glEnable (GL_DEPTH_TEST);
   my $e;
   while (($e = glGetError ()) != GL_NO_ERROR) {
      warn "ERORR ".gluErrorString ($e)."\n";
      exit;
   }
}


sub handle_sdl_events {
   my ($self) = @_;
   my $sdle = $self->{sdl_event};

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

      } elsif ($type == SDL_VIDEORESIZE) {
         $self->resize_app ($sdle->resize_w, $sdle->resize_h);

      } elsif ($type == 12) {
         ctr_log (info => "received sdl exit");
         exit;

      } else {
         ctr_log (debug => "unknown sdl event type: %d", $type);
      }
   }

}

my $collide_cnt;
my $collide_time;
sub setup_event_poller {
   my ($self) = @_;

   my $fps;
   my $fps_intv = 0.8;
   $self->{fps_w} = AE::timer 0, $fps_intv, sub {
      #printf "%.5f FPS\n", $fps / $fps_intv;
      ctr_log (profile => "%.5f secsPcoll", $collide_time / $collide_cnt) if $collide_cnt;
      ctr_log (profile => "%.5f secsPrender", $render_time / $render_cnt) if $render_cnt;
      $self->activate_ui (hud_fps =>
         ui_hud_window_transparent (
            pos => [left => 'up'],
            [text => {
               color => "#ff0000", align => "center", font => "small"
            }, sprintf ("%.1f FPS", $fps / $fps_intv)]
         )
      );
      $collide_cnt = $collide_time = 0;
      $render_cnt = $render_time = 0;
      $fps = 0;
   };

   $self->{chunk_freeer} = AE::timer 0, 2, sub {
      for my $id (keys %{$self->{compiled_chunks}}) {
         my $p = world_id2pos ($id);
         unless ($self->can_see_chunk (@$p, 1)) {
            $self->free_compiled_chunk (@$p);
            #d# warn "freeed compiled chunk $kx, $ky, $kz\n";
         }
      }

      for my $id (keys %{$self->{dirty_chunks}}) {
         unless (exists $self->{compiled_chunks}->{$_}) {
            delete $self->{dirty_chunks}->{$_};
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
   $self->{ui_timer} = AE::timer 0, 1, sub {
      for ($self->active_uis) {
         $self->{active_uis}->{$_}->animation_step;
      }
   };

   my $ltime;
   my $accum_time = 0;
   my $dt = 1 / 40;
   my $upd_pos = 0;
   my $frame_time = 0.02;
   my $last_frame;
   $self->{poll_w} = AE::timer 0, $frame_time, sub {
      my $start_time = time;
      my $dlta = $start_time - $last_frame;
      if ($dlta > $frame_time) {
         $dlta -= $frame_time;
         ctr_log (profile => "frame too late, delta is %f", $dlta);
      }

      $self->handle_sdl_events;

      $ltime = time - $frame_time if not defined $ltime;
      my $ctime = time;
      $accum_time += time - $ltime;
      $ltime = $ctime;

      while ($accum_time > $dt) {
         $self->physics_tick ($dt);
         $accum_time -= $dt;
      }

      $self->calc_visibility;

      if ($upd_pos++ > 8) {
         $self->update_player_pos (
            $self->{phys_obj}->{player}->{pos},
            $self->get_look_vector
         );
         $upd_pos = 0;
      }

      my $used = time - $start_time;
      my $rem = $frame_time - $used;

      $self->render_scene ($rem);
      $fps++;
      $last_frame = time;
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
      calc_cam_cone (0.1, 30, 72, $WIDTH, $HEIGHT, $self->get_look_vector)
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
   $self->calc_visibility; # calls ->cam_cone!

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

   if ($self->{air_select_mode}) {
      # it's soooo much faster, lol :-)
      my $pos = vfloor (vadd ($player_head, vsmul (vnorm ($rayd), 2.7)));
      return ($pos, $pos);
   }

   my ($select_pos);

   my $min_dist = 9999;
   for my $dx (-3..3) {
      for my $dy (-3..3) { # floor and above head?!
         for my $dz (-3..3) {
            # now skip the player boxes
            my $cur_box = vaddd ($head_box, $dx, $dy, $dz);
            #d# next unless $dx == 0 && $dz == 0 && $cur_box->[1] == $foot_box->[1] - 1;
            next if $dx == 0 && $dz == 0
                    && grep { $cur_box->[1] == $_ }
                          $foot_box->[1]..$head_box->[1];

            if (Games::Construder::World::is_solid_at (@$cur_box)) {
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
   my ($movement, $rot) = @_;

   my ($forw, $strafe) = (0, 0);
   if ($movement->{forward} > $movement->{backward}) {
      $forw = +3;
   } elsif ($movement->{backward} > $movement->{forward}) {
      $forw = -3;
   }

   if ($movement->{left} > $movement->{right}) {
      $strafe = -3;
   } elsif ($movement->{right} > $movement->{left}) {
      $strafe = +3;
   }

   my $xd =  sin (deg2rad ($rot));
   my $yd = -cos (deg2rad ($rot));
   my $forw = vsmul ([$xd, 0, $yd], $forw);

   $xd =  sin (deg2rad ($rot + 90));
   $yd = -cos (deg2rad ($rot + 90));
   viadd ($forw, vsmul ([$xd, 0, $yd], $strafe));
   $forw
}

sub physics_tick : event_cb {
   my ($self, $dt) = @_;

   my $player = $self->{phys_obj}->{player};
   my $below_feet_chnk =
      Games::Construder::World::has_chunk (world_pos2chunk (vsubd ($player->{pos}, 0, 1, 0)));
   my $feet_chnk =
      Games::Construder::World::has_chunk (world_pos2chunk ($player->{pos}));
   my $head_chnk =
      Games::Construder::World::has_chunk (
         world_pos2chunk (vaddd ($player->{pos}, 0, $PL_HEIGHT, 0)));
   return unless $self->{ghost_mode} || $below_feet_chnk && $feet_chnk && $head_chnk;

   my $bx = Games::Construder::World::at (@{vaddd ($player->{pos}, 0, -1, 0)});

   my $gforce = [0, -9.5, 0];
   #d#if ($bx->[0] == 15) {
   #d#   $gforce = [0, 9.5, 0];
   #d#}
   $gforce = [0,0,0] if $self->{ghost_mode};
   $gforce = vsmul ($gforce, -1) if $self->{upboost};

   if ($self->{ghost_mode}) {
      $player->{vel} = [0, 0, 0];
   } else {
      viadd ($player->{vel}, vsmul ($gforce, $dt));
   }

   if ((vlength ($player->{vel}) * $dt) > $PL_RAD) {
      $player->{vel} = vsmul (vnorm ($player->{vel}), ($PL_RAD - 0.02) / $dt);
   }
   viadd ($player->{pos}, vsmul ($player->{vel}, $dt));

   my $movement = _calc_movement ($self->{movement}, $self->{yrotate});
   $movement = vsmul ($movement, $self->{movement}->{speed} ? 2.2 : 1);
   viadd ($player->{pos}, vsmul ($movement, $dt));

   #d#warn "check player at $player->{pos}\n";
   #    my ($pos) = $chunk->collide ($player->{pos}, 0.3, \$collided);

   my $t1 = time;

   my $collide_normal;
   #d#warn "check player pos " . vstr ($player->{pos}) . "\n";

   my ($pos) =
      world_collide (
         $player->{pos},
         $PL_RAD,
         $PL_HEIGHT,
         \$collide_normal);

   #d# warn "new pos : ".vstr ($pos)." norm " . vstr ($collide_normal || []). "\n";
   unless ($self->{ghost_mode}) {
      $player->{pos} = $pos;

      if (ref $collide_normal) {
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

      } elsif ($collide_normal == 1) {
         $self->msg ("Emergency Teleport Activated. You were teleported to a free spot so you are not intermixed with something solid!");
      }
   }

   $collide_time += time - $t1;
   $collide_cnt++;
}

sub change_look_lock : event_cb {
   my ($self, $enabled) = @_;

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

   my $handled = 0;
   for ($self->active_uis) {
      if (delete $self->{active_uis}->{$_}->{key_repeat}) {
         $handled = 1;
         last;
      }
   }
   return if $handled;


   if ($name eq 'w') {
      delete $self->{movement}->{forward};
   } elsif ($name eq 's') {
      delete $self->{movement}->{backward};
   } elsif ($name eq 'a') {
      delete $self->{movement}->{left};
   } elsif ($name eq 'd') {
      delete $self->{movement}->{right};

   } elsif ($name eq 'left shift') {
      $self->{movement}->{speed} = 0;
   } elsif ($name eq 'left ctrl') {
      $self->{air_select_mode} = 0;
   } elsif ($name eq 'space') {
      $self->{upboost} = 0;
   }

}

sub show_video_settings {
   my ($self) = @_;

   my $win = ui_window ("Video Settings",
      ui_pad_box (hor =>
         ui_desc ("Ambien light: "),
         ui_subdesc (sprintf "%0.2f", $self->{res}->{config}->{ambient_light}),
         ui_range (ambl => 0.0, 0.4, 0.05, "%0.2f",
                   $self->{res}->{config}->{ambient_light}),
      ),
      ui_pad_box (hor =>
         ui_desc ("Fog: "),
         ui_subdesc ($self->fog),
      ),
      (
         map {
            ui_select_item (fog => $_, ui_desc ("$_"))
         } sort keys %FOGS
      )
   );

   $self->activate_ui (video_settings => {
      %$win,
      commands => {
         default_keys => { return => "change" }
      },
      command_cb => sub {
         my ($cmd, $arg, $need_selection) = @_;

         if ($cmd eq 'change') {
            $self->{res}->{config}->{ambient_light} = $arg->{ambl};
            $self->set_ambient_light ($self->{res}->{config}->{ambient_light});

            if ($arg->{fog} ne '') {
               $self->{res}->{config}->{fog} = $arg->{fog};
               $self->update_fog;
            }

            $self->{res}->save_config;
            $self->show_video_settings;
            return 1;
         }
      }
   });
}
sub show_mouse_settings {
   my ($self) = @_;

   my $win = ui_window ("Mouse Settings",
      ui_pad_box (hor =>
         ui_desc ("Mouse sensitivity: "),
         ui_subdesc (sprintf "%0.2f", $self->{res}->{config}->{mouse_sens}),
         ui_range (sens => 0.05, 20, 0.05, "%0.2f",
                   $self->{res}->{config}->{mouse_sens}),
      )
   );

   $self->activate_ui (mouse_settings => {
      %$win,
      commands => {
         default_keys => { return => "change" }
      },
      command_cb => sub {
         my ($cmd, $arg, $need_selection) = @_;

         if ($cmd eq 'change') {
            $self->{res}->{config}->{mouse_sens} = $arg->{sens};
            $self->{res}->save_config;
            $self->show_mouse_settings;
            return 1;
         }
      }
   });
}

sub show_audio_settings {
   my ($self) = @_;

   my $win = ui_window ("Audio Settings",
      ui_pad_box (hor =>
         ui_desc ("Music Volume: "),
         ui_subdesc (SDL::Mixer::Music::volume_music (-1)),
         ui_range (music => 0, SDL::Mixer::MIX_MAX_VOLUME, 5, "%d",
                   SDL::Mixer::Music::volume_music (-1))
      )
   );

   $self->activate_ui (audio_settings => {
      %$win,
      commands => {
         default_keys => { return => "change" }
      },
      command_cb => sub {
         my ($cmd, $arg, $need_selection) = @_;

         if ($cmd eq 'change') {
            SDL::Mixer::Music::volume_music ($arg->{music});
            $self->{res}->{config}->{volume_music} = $arg->{music};
            $self->{res}->save_config;
            $self->show_audio_settings;
            return 1;
         }
      }
   });
}

sub show_key_help {
   my ($self) = @_;

   $self->activate_ui (key_help =>
      ui_window ("Client Key Bindings",
         ui_desc (
            "These key bindings work globally "
            . "when not in any dialog in the client."),
         ui_subdesc (
            "(For more key bindings hit [F2] to bring up the server menu!)"),
         ui_key_explain (
            [qw/w s a d/], "Move forward / backward / left / right."),
         ui_key_explain (
            "left shift",  "Hold to speedup [w/s/a/d] movement."),
         ui_key_explain (
            "space",
            "Jump / Give upward thrust."),
         ui_key_explain (
            "f",
            "Toggle mouse look."),
         ui_key_explain (
            "left ctrl",
            "Hold to move highlight into the free air (for building for example)."),
         ui_key_explain ("g",         "Toggle ghost mode (developer stuff)."),
         ui_key_explain ([qw/F5 F6/], "De-/Increase visibility radius."),
      )
   );
}

sub show_credits {
   my ($self) = @_;

   my $si = $self->{server_info};

   $self->activate_ui (credits => ui_window ("About / Credits",
      ui_caption (sprintf "Client: G::C::Client %s", $Games::Construder::VERSION),
      ui_subdesc ("Code: Robin Redeker"),
      ui_caption (sprintf "Server: %s", $si->{version}),
      map {
         ref $_
            ? (ui_subdesc ("* $_->[0]", font => "small"),
               ui_small_text ($_->[1], align => "center", wrap => 100))
            : ui_subdesc ($_, font => "small")
      } @{$si->{credits}}
   ));
}

sub esc_menu {
   my ($self) = @_;

   my $ui =
      ui_window ("Construder Client",
         ui_subdesc (
            "(To activate the menu item, press the key in the square brackets)"),
         ui_key_explain (F1 => "Keybindings Help (Client)"),
 # not yet implemented:
 #        ui_key_explain (s  => "Connection Settings"),
 #        ui_key_explain (d  => "Disconnect"),
 #        ui_key_explain (c  => "Connect"),
 #        ui_key_explain (a  => "Audio Options"),
         ui_key_explain (m  => "Mouse Options"),
         ui_key_explain (v  => "Video Options"),
         ui_key_explain (f  => "Toggle Fullscreen"),
         ui_key_explain (t  => "About"),
         ui_key_explain (q  => "Exit (Press the 'q' key)"),
      );

   $self->activate_ui (esc_menu => {
      %$ui,
      commands => {
         default_keys => {
            q => "exit",
            t => "credits",
            f => "fullscreen",
            m => "mouse",
            v => "video",
            a => "audio",
         }
      },
      command_cb => sub {
         my ($cmd, $arg, $need_selection) = @_;

         if ($cmd eq 'exit') {
            $self->exit_app;
            return 1;

         } elsif ($cmd eq 'credits') {
            $self->deactivate_ui ('esc_menu');
            $self->show_credits;
            return 1;

         } elsif ($cmd eq 'audio') {
            $self->deactivate_ui ('esc_menu');
            $self->show_audio_settings;
            return 1;

         } elsif ($cmd eq 'mouse') {
            $self->deactivate_ui ('esc_menu');
            $self->show_mouse_settings;
            return 1;

         } elsif ($cmd eq 'video') {
            $self->deactivate_ui ('esc_menu');
            $self->show_video_settings;
            return 1;

         } elsif ($cmd eq 'fullscreen') {
            $self->{app}->fullscreen;
         }
      }
   });
}

sub msg {
   my ($self, $msg, $cb) = @_;

   unless (defined $msg) {
      $self->deactivate_ui ('cl_msgbox');
      return;
   }

   $self->activate_ui (cl_msgbox => ui_window ("Client Message", ui_desc ($msg)));
}

sub activate_ui {
   my ($self, $ui, $desc) = @_;

   if (my $obj = $self->{active_uis}->{$ui}) {
      ctr_prof ("act_ui($ui)", sub {
         $obj->update ($desc);
      });
      return;
   }

   my $obj = delete $self->{inactive_uis}->{$ui};

   $obj ||=
      Games::Construder::Client::UI->new (
         W => $WIDTH, H => $HEIGHT, res => $self->{res}, name => $ui);

   ctr_prof ("act_ui($ui)", sub {
      $obj->update ($desc);
   });

   my $oobj = delete $self->{active_uis}->{$ui};
   $oobj->active (0) if $oobj;
   $self->{active_uis}->{$ui} = $obj;
   $obj->active (1);

   unless ($obj->{sticky}) {
      push @{$self->{active_ui_stack}}, [$ui, $obj]
   }
}

sub deactivate_ui {
   my ($self, $ui) = @_;
   @{$self->{active_ui_stack}} = grep {
      $_->[0] ne $ui
   } @{$self->{active_ui_stack}};

   my $obj = delete $self->{active_uis}->{$ui};
   if ($obj) {
      $obj->active (0);
      $self->{inactive_uis}->{$ui} = $obj;
   }
}

sub active_uis {
   my ($self) = @_;

   my (@active_uis) = grep {
      $self->{active_uis}->{$_}->{sticky}
   } (keys %{$self->{active_uis}});

   if (@{$self->{active_ui_stack}}) {
      unshift @active_uis, $self->{active_ui_stack}->[-1]->[0];
   }

   @active_uis
}

sub input_key_down : event_cb {
   my ($self, $key, $name, $unicode) = @_;

   my $handled = 0;

   for ($self->active_uis) {
      my $obj = $self->{active_uis}->{$_};
      $obj->input_key_press ($key, $name, chr ($unicode), \$handled);
      $self->deactivate_ui ($_) if $handled == 2;
      if ($handled == 1 && $obj->{active}) {
         $obj->{key_repeat} = AE::timer 0.2, 0.1, sub {
            my $handled;
            $obj->input_key_press ($key, $name, chr ($unicode), \$handled);
         };
      }
      last if $handled;
   }
   return if $handled;

   if ($name eq 'escape') {
      $self->esc_menu;
      return;

   } elsif ($name eq 'f1') {
      $self->show_key_help;
      return;
   }

   ctr_log (debug => "key press %s (%s)", $key, $name);

   my $move_x;

   if ($name eq 'space') {
      $self->{upboost} = 1;
      viaddd ($self->{phys_obj}->{player}->{vel}, 0, 5, 0);
   } elsif ($name eq 'g') {
      $self->{ghost_mode} = not $self->{ghost_mode};
   } elsif ($name eq 'f') {
      $self->change_look_lock (not $self->{look_lock});
   } elsif ($name eq 'left ctrl') {
      $self->{air_select_mode} = 1;
   } elsif ($name eq 'left shift') {
      $self->{movement}->{speed} = 1;
   } elsif ($name eq 'w') {
      $self->{movement}->{forward} =
         $self->{movement}->{backward} + 1;
   } elsif ($name eq 's') {
      $self->{movement}->{backward} =
         $self->{movement}->{forward} + 1;
   } elsif ($name eq 'a') {
      $self->{movement}->{left} =
         $self->{movement}->{right} + 1;
   } elsif ($name eq 'd') {
      $self->{movement}->{right} =
         $self->{movement}->{left} + 1;
   } elsif ($name eq 'f5') {
      $self->visibility_radius ($PL_VIS_RAD - 1);
   } elsif ($name eq 'f6') {
      $self->visibility_radius ($PL_VIS_RAD + 1);
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
      my $sens = $self->{res}->{config}->{mouse_sens};
      $self->{yrotate} += ($xr / $WIDTH) * 15 * $sens;
      $self->{xrotate} += ($yr / $HEIGHT) * 15 * $sens;
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
   return unless $down;

   my $sbp = $self->{selected_box};
   my $sbbp = $self->{selected_build_box};
   $self->position_action ($sbp, $sbbp, $btn);
}

sub update_player_pos : event_cb {
   my ($self, $pos) = @_;
}

sub visible_chunks_changed : event_cb {
   my ($self, $new, $old, $req) = @_;
   # TODO: $req might be issued again and again with the same chunks,
   #       we should mabye rate limit that for more bandwidth friendly
   #       behaviour
}

sub visibility_radius : event_cb {
   my ($self, $radius) = @_;
   $radius = 6 if $radius > 6; # limit, or it usuall kills server :-/
   $PL_VIS_RAD = $radius;
   $FAR_PLANE = ($radius * 12) * 0.7;
   glFogf (GL_FOG_START, $FAR_PLANE - 20);
   glFogf (GL_FOG_END,   $FAR_PLANE - 1);
   ctr_log (info => "changed visibility radius to %d", $PL_VIS_RAD);
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License.

=cut

1;

