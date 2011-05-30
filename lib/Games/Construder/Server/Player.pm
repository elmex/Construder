package Games::Construder::Server::Player;
use Devel::FindRef;
use common::sense;
use AnyEvent;
use Games::Construder::Server::World;
use Games::Construder::Vector;
use base qw/Object::Event/;
use Scalar::Util qw/weaken/;
use Compress::LZF;

=head1 NAME

Games::Construder::Server::Player - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Construder::Server::Player->new (%args)

=cut

my $PL_VIS_RAD = 4;

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;

   return $self
}

sub _check_file {
   my ($self) = @_;
   my $pld = $Games::Construder::Server::Resources::PLAYERDIR;
   my $file = "$pld/$self->{name}.json";
   return unless -e "$file";

   if (open my $plf, "<", $file) {
      binmode $plf, ":raw";
      my $cont = do { local $/; <$plf> };
      my $data = eval { JSON->new->relaxed->utf8->decode ($cont) };
      if ($@) {
         warn "Couldn't parse player data from file '$file': $!\n";
         return;
      }

      return $data

   } else {
      warn "Couldn't open player file $file: $!\n";
      return;
   }
}

sub _initialize_player {
   my ($self) = @_;
   my $data = {
      name      => $self->{name},
      happyness => 100,
      bio       => 100,
      score     => 0,
      pos       => [0, 0, 0],
      inv       => {
         2  => 30, # 30 stones
         16 => 50, # 50 brickwalls
         15 => 20, # 20 concretes
         40 => 10, # 10 flood lights
         60 => 20, # 20 proteins
      },
      slots => {
         selection => [2, 16, 40],
         selected  => 0
      },
   };

   $data
}

sub load {
   my ($self) = @_;

   my $data = $self->_check_file;
   unless (defined $data) {
      $data = $self->_initialize_player;
   }

   $self->{data} = $data;
}

sub save {
   my ($self) = @_;
   my $cont = JSON->new->pretty->utf8->encode ($self->{data});
   my $pld = $Games::Construder::Server::Resources::PLAYERDIR;
   my $file = "$pld/$self->{name}.json";

   if (open my $plf, ">", "$file~") {
      binmode $plf, ":raw";
      print $plf $cont;
      close $plf;

      if (-s "$file~" != length ($cont)) {
         warn "Couldn't write out player file completely to '$file~': $!\n";
         return;
      }

      unless (rename "$file~", "$file") {
         warn "Couldn't rename $file~ to $file: $!\n";
         return;
      }

      warn "saved player $self->{name} to $file.\n";

   } else {
      warn "Couldn't open player file $file~ for writing: $!\n";
      return;
   }
}

sub init {
   my ($self) = @_;
   $self->load;
   $self->save;
   my $wself = $self;
   weaken $wself;
   $self->{hud1_tmr} = AE::timer 0, 1, sub {
      $wself->update_hud_1;
   };
   $self->{save_timer} = AE::timer 0, 15, sub {
      $wself->add_score (100);
      $wself->save;
   };
   my $tick_time = time;
   $self->{tick_timer} = AE::timer 0.25, 0.25, sub {
      my $cur = time;
      $wself->player_tick ($cur - $tick_time);
      $tick_time = $cur;
   };

   $self->{logic}->{unhappy_rate} = 0.25; # 0.25% per second

   $self->update_score;
   $self->update_slots;
   $self->send_visible_chunks;
   $self->teleport ();
}

sub player_tick {
   my ($self, $dt) = @_;

   my $logic = $self->{logic};

   $self->{data}->{happyness} -= $dt * $logic->{unhappy_rate};
   if ($self->{data}->{happyness} < 0) {
      $self->{data}->{happyness} = 0;
      $self->{logic}->{bio_rate} = 5;

   } elsif ($self->{data}->{happyness} > 0) {
      $self->{logic}->{bio_rate} = 0;
   }

   $self->{data}->{bio} -= $dt * $logic->{bio_rate};
   if ($self->{data}->{bio} <= 0) {
      $self->{data}->{bio} = 0;

      if (!$self->try_eat_something) { # danger: this maybe recurses into player_tick :)
         $self->starvation (1);
      }
   } else {
      $self->starvation (0);
   }
}

sub starvation {
   my ($self, $starves) = @_;

   if ($starves) {
      unless ($self->{death_timer}) {
         $self->show_bio_warning (1);
         $self->{death_timer} = AE::timer 30, 0, sub {
            $self->kill_player;
            delete $self->{death_timer};
            $self->show_bio_warning (0);
         };
      }

   } else {
      if (delete $self->{death_timer}) {
         $self->show_bio_warning (0);
      }
   }
}

sub decrease_inventory {
   my ($self, $type) = @_;

   my $cnt = $self->{data}->{inv}->{$type}--;
   if ($self->{data}->{inv}->{$type} <= 0) {
      delete $self->{data}->{inv}->{$type};
   }

   if ($self->{shown_uis}->{player_inv}) {
      $self->show_inventory; # update if neccesary
   }

   $cnt > 0
}

sub try_eat_something {
   my ($self) = @_;

   my (@max_e) = sort {
      $b->[1] <=> $a->[1]
   } grep { $_->[1] } map {
      my $obj = $Games::Construder::Server::RES->get_object_by_type ($_);
      [$_, $obj->{bio_energy}]
   } keys %{$self->{data}->{inv}};

   while (@max_e) {
      my $res = shift @max_e;
      if ($self->decrease_inventory ($res->[0])) {
         $self->refill_bio ($res->[1]);
         return 1;
      }
   }

   return 0;
}

sub refill_bio {
   my ($self, $amount) = @_;

   $self->{data}->{bio} += $amount;
   $self->{data}->{bio} = 100
      if $self->{data}->{bio} > 100;

   if ($self->{data}->{bio} > 0) {
      $self->starvation (0); # make sure we don't starve anymore
   }

   # no refresh now. wait for next tick.
   # $self->player_tick (0); # no change, just cleanup state
}

sub kill_player {
   my ($self) = @_;
   $self->teleport ([0, 0, 0]);
   $self->{data}->{happyness} = 100;
   $self->{data}->{bio}       = 100;
   $self->{data}->{score}    -=
      int ($self->{data}->{score} * (20 / 100)); # 20% score loss
}

sub show_bio_warning {
   my ($self, $enable) = @_;
   unless ($enable) {
      $self->display_ui ('player_bio_warning');
      return;
   }

   $self->display_ui (player_bio_warning => {
      window => {
         sticky => 1,
         pos => [center => 'center', 0, -0.25],
         alpha => 0.3,
      },
      layout => [
         text => { font => "big", color => "#ff0000", wrap => 30 },
          "Warning: Bio energy level low.\nDeath imminent, please eat something!",
      ]
   });
}

sub logout {
   my ($self) = @_;
   $self->save;
   delete $self->{displayed_uis};
   delete $self->{upd_score_hl_tmout};
   delete $self->{death_timer};
   warn "player $self->{name} logged out\n";
#d#  print Devel::FindRef::track $self;
}

my $world_c = 0;

sub _visible_chunks {
   my ($from, $chnk) = @_;

   my $plchnk = world_pos2chnkpos ($from);
   $chnk ||= $plchnk;

   my @c;
   for my $dx (-$PL_VIS_RAD..$PL_VIS_RAD) {
      for my $dy (-$PL_VIS_RAD..$PL_VIS_RAD) {
         for my $dz (-$PL_VIS_RAD..$PL_VIS_RAD) {
            my $cur = [$chnk->[0] + $dx, $chnk->[1] + $dy, $chnk->[2] + $dz];
            next if vlength (vsub ($cur, $plchnk)) >= $PL_VIS_RAD;
            push @c, $cur;
         }
      }
   }

   @c
}

sub update_pos {
   my ($self, $pos) = @_;

   my $opos = $self->{data}->{pos};
   $self->{data}->{pos} = $pos;

   my $oblk = vfloor ($opos);
   my $nblk = vfloor ($pos);
   return unless (
         $oblk->[0] != $nblk->[0]
      || $oblk->[1] != $nblk->[1]
      || $oblk->[2] != $nblk->[2]
   );

   my $last_vis = $self->{last_vis} || {};
   my $next_vis = {};
   my @chunks   = _visible_chunks ($pos);
   my @new_chunks;
   for (@chunks) {
      my $id = world_pos2id ($_);
      unless ($last_vis->{$id}) {
         push @new_chunks, $_;
      }
      $next_vis->{$id} = 1;
   }
   $self->{last_vis} = $next_vis;

   if (@new_chunks) {
      $self->send_client ({ cmd => "chunk_upd_start" });
      $self->send_chunk ($_) for @new_chunks;
      $self->send_client ({ cmd => "chunk_upd_done" });
   }
}

# TODO:
#  X light-setzen per maus
#  X player inkrementell updates der welt schicken
#  - modelle einbauen
#  - objekte weiter eintragen
sub chunk_updated {
   my ($self, $chnk) = @_;

   my $plchnk = world_pos2chnkpos ($self->{data}->{pos});
   my $divvec = vsub ($chnk, $plchnk);
   return if vlength ($divvec) >= $PL_VIS_RAD;

   $self->send_chunk ($chnk);
}

sub send_visible_chunks {
   my ($self) = @_;

   $self->send_client ({ cmd => "chunk_upd_start" });

   my @chnks = _visible_chunks ($self->{data}->{pos});
   $self->send_chunk ($_) for @chnks;

   warn "done sending " . scalar (@chnks) . " visible chunks.\n";
   $self->send_client ({ cmd => "chunk_upd_done" });
}

sub send_chunk {
   my ($self, $chnk) = @_;

   # only send chunk when allcoated, in all other cases the chunk will
   # be sent by the chunk_changed-callback by the server (when it checks
   # whether any player might be interested in that chunk).
   my $data = Games::Construder::World::get_chunk_data (@$chnk);
   return unless defined $data;
   $self->send_client ({ cmd => "chunk", pos => $chnk }, compress ($data));
}

sub add_score {
   my ($self, $score) = @_;
   $self->{data}->{score} += $score;
   $self->update_score (1);
}

sub update_score {
   my ($self, $hl) = @_;

   my $s = $self->{data}->{score};

   $self->display_ui (player_score => {
      window => {
         sticky  => 1,
         pos     => [center => "up"],
         alpha   => $hl ? 1 : 0.6,
      },
      layout => [
         box => {
            border => { color => $hl ? "#ff0000" : "#777700" },
            padding => ($hl ? 10 : 2),
            align => "hor",
         },
         [text => {
            font => "normal",
            color => "#aa8800",
            align => "center"
          }, "Score:"],
         [text => {
             font => "big",
             color => $hl ? "#ff0000" : "#aa8800",
          },
          $s]
      ]
   });
   if ($hl) {
      $self->{upd_score_hl_tmout} = AE::timer 1, 0, sub {
         $self->update_score;
         delete $self->{upd_score_hl_tmout};
      };
   }
}

sub update_slots {
   my ($self) = @_;

   my $slots = $self->{data}->{slots};
   my $inv   = $self->{data}->{inv};

   my @slots;
   for (my $i = 0; $i < 10; $i++) {
      my $cur = $slots->{selection}->[$i];

      my $border = "#0000ff";
      if ($i == $slots->{selected}) {
         $border = "#ff0000";
      }

      push @slots,
      [box => { dir => "vert", padding => 3 },
         [box => { padding => 2, border => { color => $border } },
           [model => { color => "#00ff00", width => 50 }, $cur]],
         [text => { font => "small", color => "#999999" },
          $cur . ": " . $inv->{$cur}]
      ];
   }

   $self->display_ui (player_slots => {
      window => {
         sticky => 1,
         pos    => [left => "down"],
      },
      layout => [
         box => { }, @slots
      ],
      commands => {
         default_keys => {
            (map { ("$_" => "slot_$_") } 0..9)
         },
      },

   }, sub {
      if ($_[1] =~ /slot_(\d+)/) {
         my $i = 0;
         if ($1 eq '0') {
            $i = 9;
         } else {
            $i = $1 - 1;
         }
         $self->{data}->{slots}->{selected} = $i;
         $self->update_slots;
      }
   });
}

sub update_hud_1 {
   my ($self) = @_;

   my $abs_pos  = vfloor ($self->{data}->{pos});
   my $chnk_pos = world_pos2chnkpos ($self->{data}->{pos});
   my $sec_pos  = world_chnkpos2secpos ($chnk_pos);

   my $sinfo = $Games::Construder::Server::CHNK->sector_info (@$chnk_pos);

   $self->display_ui (player_hud_1 => {
      window => {
         sticky => 1,
         pos => [right => 'up'],
         alpha => 0.8,
      },
      layout => [
        box => { dir => "vert" },
        [
           box => { dir => "hor" },
           [box => { dir => "vert", padding => 2 },
              [text => { color => "#888888", font => "small" }, "Pos"],
              [text => { color => "#888888", font => "small" }, "Chunk"],
              [text => { color => "#888888", font => "small" }, "Sector"],
              [text => { color => "#888888", font => "small" }, "Type"],
           ],
           [box => { dir => "vert", padding => 2 },
              [text => { color => "#ffffff", font => "small" },
                 sprintf ("%3d,%3d,%3d", @$abs_pos)],
              [text => { color => "#ffffff", font => "small" },
                 sprintf ("%3d,%3d,%3d", @$chnk_pos)],
              [text => { color => "#ffffff", font => "small" },
                 sprintf ("%3d,%3d,%3d", @$sec_pos)],
              [text => { color => "#ffffff", font => "small" },
                 sprintf ("%s, %0.5f", $sinfo->{type}, $sinfo->{param})],
           ]
        ],
        [box => { },
           [text => { align => "right", font => "big", color => "#ffff55", max_chars => 4 },
              sprintf ("%d%%", $self->{data}->{happyness})],
           [text => { align => "center", color => "#888888" }, "happy"],
        ],
        [box => { },
           [text => { align => "right", font => "big", color => "#55ff55", max_chars => 4 },
              sprintf ("%d%%", $self->{data}->{bio})],
           [text => { align => "center", color => "#888888" }, "bio"],
        ],
      ],
      commands => {
         default_keys => {
            f1 => "help",
            i  => "inventory",
            f9 => "teleport_home",
            f12 => "exit_server",
         },
      },
   }, sub {
      my $cmd = $_[1];
      if ($cmd eq 'inventory') {
         $self->show_inventory;
      } elsif ($cmd eq 'help') {
         $self->show_help;
      } elsif ($cmd eq 'teleport_home') {
         $self->teleport ([0, 0, 0]);
      } elsif ($cmd eq 'exit_server') {
         exit;
      }
   });
}

sub show_inventory_selection {
   my ($self, $type) = @_;

   warn "SHOW INV SEL $type\n";
   my $o = $Games::Construder::Server::RES->get_object_by_type ($type);

   $self->display_ui (player_inv_sel => {
      window => {
         pos => [center => 'center'],
      },
      layout => [
         box => { dir => "vert" },
          [text => { color => "#ffffff", font => "big" }, "Selected: " . $o->{name}],
          [text => { color => "#ffffff", font => "normal", wrap => 50 },
             "* You can put it into a slot by pressing one of the number keys 0 to 9" ],
      ],
      commands => {
         default_keys => {
            (map { ("$_" => "slot_$_") } 0..9)
         }
      }
   }, sub {
      if ($_[1] =~ /slot_(\d+)/) {
         my $i = 0;
         if ($1 eq '0') {
            $i = 9;
         } else {
            $i = $1 - 1;
         }
         $self->{data}->{slots}->{selection}->[$i] = $type;
         $self->update_slots;
         $self->display_ui ('player_inv_sel');
      }
   });
}

sub show_inventory {
   my ($self) = @_;

   my $inv = $self->{data}->{inv};
   warn "SHOW INV $self->{shown_uis}->{player_inv}|\n";

   my @grid;

   my @keys = sort { $a <=> $b } keys %$inv;
   my @shortcuts = qw/
      1 q a y 2 w s x
      3 e d c 4 r f v
      5 t g b 6 z h n
   /;

   for (0..4) {
      my @row;
      for (0..3) {
         my $i = (shift @keys) || 1;
         my $o = $Games::Construder::Server::RES->get_object_by_type ($i);
         push @row, [$i, $inv->{$i}, $o, shift @shortcuts];
      }
      push @grid, \@row;
   }

   $self->display_ui (player_inv => {
      window => {
         pos => [center => 'center'],
      },
      layout => [
         box => { dir => "vert" },
         [text => { font => "big", color => "#FFFFFF" }, "Inventory"],
         [text => { font => "small", color => "#888888" },
          "(Select a resource by shortcut key or up/down and hit return.)"],
         [box => { },
         (map {
            [box => { dir => "vert", padding => 4 },
               map {
                  [select_box => {
                     dir => "vert", align => "center", arg => "item", tag => $_,
                     padding => 2,
                     bgcolor => "#333333",
                     border => { color => "#555555", width => 2 },
                     select_border => { color => "#ffffff", width => 2 },
                     aspect => 1
                   },
                     [text => { align => "center", color => "#ffffff" },
                      $_->[1] ? $_->[1] . "x " : ""],
                     [model => { align => "center", width => 60 }, $_->[0]],
                     [text  => { font => "small", align => "center",
                                 color => "#ffffff" },
                      $_->[0] == 1 ? "<empty>" : "[$_->[3]] $_->[2]->{name}"]
                  ]

               } @$_
            ]
         } @grid)
         ]
      ],
      commands => {
         default_keys => {
            return => "select",
            (map { map { $_->[3] => "short_$_->[0]" } @$_ } @grid)
         }
      }
   }, sub {
      warn "ARG: $_[2]->{item}|" . join (',', keys %{$_[2]}) . "\n";

      my $cmd = $_[1];
      warn "CMD $cmd\n";
      if ($cmd eq 'select') {
         my $item = $_[2]->{item};
         $self->display_ui ("player_inv");
         $self->show_inventory_selection ($item->[0]);

      } elsif ($cmd =~ /short_(\d+)/) {
         $self->display_ui ("player_inv");
         $self->show_inventory_selection ($1);
      }
   });
}

sub show_help {
   my ($self) = @_;

   my $help_txt = <<HELP;
[ w a s d ]
forward, left, backward, right
[ shift ]
holding down shift doubles your speed
[ f ]
toggle mouse look
[ g ]
enable gravitation and collision detection
[ i ]
show up inventory
[ space ]
jump
[ escape ]
close window or quit game
[ left, right mouse button ]
dematerialize and materialize
[ F9 ]
teleport to the starting point
HELP

   $self->send_client ({ cmd => activate_ui => ui => "player_help", desc => {
      window => {
         extents => [center => center => 0.8, 1],
         alpha => 1,
         color => "#000000",
         prio => 1000,
      },
      elements => [
         {
            type => "text", extents => ["center", 0.01, 0.9, "font_height"],
            font => "big", color => "#ffffff",
            align => "center",
            text => "Help:"
         },
         {
            type => "text", extents => ["center", "bottom_of 0", 1, 0.9],
            font => "small", color => "#ffffff",
            align => "center",
            text => $help_txt,
         },
      ]
   } });
}

sub set_debug_light {
   my ($self, $pos) = @_;
   world_mutate_at ($pos, sub {
      my ($data) = @_;
      $data->[1] = $data->[1] > 8 ? 1 : 15;
      return 1;
   });
}

sub start_materialize {
   my ($self, $pos) = @_;

   my $id = world_pos2id ($pos);
   if ($self->{materializings}->{$id}) {
      return;
   }

   $self->send_client ({
      cmd => "highlight", pos => $pos, color => [0, 1, 1], fade => 1, solid => 1
   });
   $self->{materializings}->{$id} = 1;
   world_mutate_at ($pos, sub {
      my ($data) = @_;
      $data->[0] = 1;
      return 1;
   }, no_light => 1);

   my $tmr;
   $tmr = AE::timer 1, 0, sub {
      world_mutate_at ($pos, sub {
         my ($data) = @_;
         my $t = $self->{data}->{slots}->{selection}->[$self->{data}->{slots}->{selected}];
         $data->[0] = $t;

         delete $self->{materializings}->{$id};
         undef $tmr;
         return 1;
      });
   };

}

sub start_dematerialize {
   my ($self, $pos) = @_;

   my $id = world_pos2id ($pos);
   if ($self->{dematerializings}->{$id}) {
      return;
   }

   $self->send_client ({ cmd => "highlight", pos => $pos, color => [1, 0, 1], fade => -1.5 });
   $self->{dematerializings}->{$id} = 1;

   my $tmr;
   $tmr = AE::timer 1.5, 0, sub {
      world_mutate_at ($pos, sub {
         my ($data) = @_;
         my $obj = $Games::Construder::Server::RES->get_object_by_type ($data->[0]);
         my $succ = 0;
         unless ($obj->{untransformable}) {
            $self->{data}->{inventory}->{material}->{$data->[0]}++;
            $data->[0] = 0;
            $succ = 1;
         }
         delete $self->{dematerializings}->{$id};
         undef $tmr;
         return $succ;
      });
   };
}

sub send_client : event_cb {
   my ($self, $hdr, $body) = @_;
}

sub teleport {
   my ($self, $pos) = @_;

   $pos ||= $self->{data}->{pos};
   $self->send_client ({ cmd => "place_player", pos => $pos });
}

sub display_ui {
   my ($self, $id, $dest, $cb) = @_;

   unless ($dest) {
      $self->send_client ({ cmd => deactivate_ui => ui => $id });
      delete $self->{displayed_uis}->{$id};
      delete $self->{shown_uis}->{$id};
      return;
   }

   $self->{displayed_uis}->{$id} = $cb if $cb;
   $self->send_client ({ cmd => activate_ui => ui => $id, desc => $dest });
   $self->{shown_uis}->{$id}++;
}

sub ui_res : event_cb {
   my ($self, $ui, $cmd, $arg) = @_;
   warn "ui response $ui: $cmd ($arg)\n";

   if (my $u = $self->{displayed_uis}->{$ui}) {
      $u->($ui, $cmd, $arg);
   }

   if ($cmd eq 'cancel') {
      delete $self->{shown_uis}->{$ui};
      delete $self->{displayed_uis}->{$ui};
   }
}

sub DESTROY {
   my ($self) = @_;
   warn "player $self->{name} [$self] destroyed!\n";
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
