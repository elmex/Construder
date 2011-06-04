package Games::Construder::Server::Player;
use Devel::FindRef;
use common::sense;
use AnyEvent;
use Games::Construder::Server::World;
use Games::Construder::Server::UI;
use Games::Construder::Server::Objects;
use Games::Construder::Vector;
use base qw/Object::Event/;
use Scalar::Util qw/weaken/;
use Compress::LZF;
use Math::Trig qw/acos rad2deg/;

=head1 NAME

Games::Construder::Server::Player - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Construder::Server::Player->new (%args)

=cut

my $PL_VIS_RAD = 3;
my $PL_MAX_INV = 20;

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
   my $inv = $Games::Construder::Server::RES->get_initial_inventory;
   my $data = {
      name      => $self->{name},
      happyness => 100,
      bio       => 100,
      score     => 0,
      pos       => [0, 0, 0],
      inv       => $inv,
      slots => {
         selection => [keys %$inv],
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

sub push_tick_change {
   my ($self, $key, $amt) = @_;
   push @{$self->{tick_changes}}, [$key, $amt];
}

sub player_tick {
   my ($self, $dt) = @_;

   my $logic = $self->{logic};

   while (@{$self->{tick_changes}}) {
      my ($k, $a) = @{shift @{$self->{tick_changes}}};

      if ($k eq 'happyness' || $k eq 'bio') {
         $self->{data}->{$k} += $a;

         if ($self->{data}->{$k} > 100) {
            $self->{data}->{$k} = 100;
         }

      } elsif ($k eq 'score') {
         my $happy = $Games::Construder::Server::RES->score2happyness ($a);
         $self->{data}->{happyness} += int ($happy + 0.5);

         if ($self->{data}->{happyness} < 90) {
            $a = 0;
         } elsif ($self->{data}->{happyness} > 100) {
            $self->{data}->{happyness} = 100;
         }

         if ($a) {
            $self->update_score ($a);
            $self->{data}->{score} += $a;
            $self->{data}->{score} = int $self->{data}->{score};
         }
      }
   }

   $self->{data}->{happyness} -= $dt * $logic->{unhappy_rate};
   if ($self->{data}->{happyness} < 0) {
      $self->{data}->{happyness} = 0;
      $self->{logic}->{bio_rate} = 5;

   } elsif ($self->{data}->{happyness} > 0) {
      $self->{logic}->{bio_rate} = 0.03;
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

   my $hunger = 100 - $self->{data}->{bio};
   $self->try_eat_something ($hunger);
}

sub starvation {
   my ($self, $starves) = @_;

   if ($starves) {
      unless ($self->{death_timer}) {
         my $cnt = 30;
         $self->{death_timer} = AE::timer 0, 1, sub {
            if ($cnt-- <= 0) {
               $self->kill_player;
               delete $self->{death_timer};
               $self->show_bio_warning (0);
            } else {
               $self->show_bio_warning ($cnt);
            }
         };
      }

   } else {
      if (delete $self->{death_timer}) {
         $self->show_bio_warning (0);
      }
   }
}

sub has_inventory_space {
   my ($self, $type, $cnt) = @_;
   $cnt ||= 1;
   my ($spc, $max) = $self->inventory_space_for ($type);
   $spc >= $cnt
}

sub increase_inventory {
   my ($self, $type, $cnt) = @_;

   $cnt ||= 1;

   my ($spc, $max) = $self->inventory_space_for ($type);
   if ($spc > 0) {
      $cnt = $spc if $spc < $cnt;
      $self->{data}->{inv}->{$type} += $cnt;

      if ($self->{shown_uis}->{player_inv}) {
         $self->show_inventory; # update if neccesary
      }

      $self->update_slots;

      return 1
   }
   0
}

sub decrease_inventory {
   my ($self, $type) = @_;

   my $cnt = 0;

   if ($type eq 'all') {
      $self->{data}->{inv} = {};

   } else {
      $cnt = $self->{data}->{inv}->{$type}--;
      if ($self->{data}->{inv}->{$type} <= 0) {
         delete $self->{data}->{inv}->{$type};
      }
   }

   if ($self->{shown_uis}->{player_inv}) {
      $self->show_inventory; # update if neccesary
   }

   $self->update_slots;

   $cnt > 0
}

sub try_eat_something {
   my ($self, $amount) = @_;

   my (@max_e) = sort {
      $b->[1] <=> $a->[1]
   } grep { $_->[1] } map {
      my $obj = $Games::Construder::Server::RES->get_object_by_type ($_);
      [$_, $obj->{bio_energy}]
   } keys %{$self->{data}->{inv}};

   return 0 unless @max_e;

   if ($amount) {
      my $item = $max_e[0];
      if ($item->[1] <= $amount) {
         if ($self->decrease_inventory ($item->[0])) {
            $self->refill_bio ($item->[1]);
            return 1;
         }
      }

   } else {
      while (@max_e) { # eat anything!
         my $res = shift @max_e;
         if ($self->decrease_inventory ($res->[0])) {
            $self->refill_bio ($res->[1]);
            return 1;
         }
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
}

sub kill_player {
   my ($self) = @_;
   $self->teleport ([0, 0, 0]);
   $self->decrease_inventory ('all');
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

   $self->display_ui (player_bio_warning => ui_player_bio_warning ($enable));
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
   my ($self, $pos, $lv) = @_;

   my $opos = $self->{data}->{pos};
   $self->{data}->{pos} = $pos;
   my $olv = $self->{data}->{look_vec} || [0,0,0];
   $self->{data}->{look_vec} = vnorm ($lv);

   my $oblk = vfloor ($opos);
   my $nblk = vfloor ($pos);

   my $new_pos = vlength (vsub ($oblk, $nblk)) > 0;
   my $new_lv  = vlength (vsub ($olv, $lv)) > 0.05;
   my $dnew_lv = vlength (vsub ($olv, $lv));

   if ($new_pos || $new_lv) {
      if ($self->{shown_uis}->{player_nav}) {
         $self->show_navigator;
      }
   }

   return unless $new_pos;

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

sub msg {
   my ($self, $error, $msg) = @_;

   $self->display_ui (player_msg => {
      window => {
         pos => [center => "center", 0, 0.25],
         alpha => 0.6,
      },
      layout => [
         text => { font => "big", color => $error ? "#ff0000" : "#ffffff", wrap => 20 },
         $msg
      ]
   });

   $self->{msg_tout} = AE::timer (($error ? 3 : 1), 0, sub {
      $self->display_ui ('player_msg');
      delete $self->{msg_tout};
   });
}

sub update_score {
   my ($self, $hl) = @_;

   my $s = $self->{data}->{score};

   $self->display_ui (player_score => ui_player_score ($s, $hl));
   if ($hl) {
      $self->{upd_score_hl_tmout} = AE::timer 1.5, 0, sub {
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

      my $o = $Games::Construder::Server::RES->get_object_by_type ($cur);
      my ($spc, $max) = $self->inventory_space_for ($cur);

      push @slots,
      [box => { padding => 2, aspect => 1 },
      [box => { dir => "vert", padding => 2, border => { color => $border }, aspect => 1 },
         [box => { padding => 2, align => "center" },
           [model => { color => "#00ff00", width => 40 }, $cur]],
         [text => { font => "small", color => $cur && $inv->{$cur} <= 0 ? "#990000" : "#999999", align => "center" },
          sprintf ("[%d] %d/%d", $i + 1, $inv->{$cur} * 1, $cur ? $max : 0)]
      ]];
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

sub _range_color {
   my ($perc, $low_ok) = @_;
   my ($first, $second) = (
      int (($low_ok / 2) / 10) * 10,
      $low_ok
   );

     $perc < $first  ? "#ff5555"
   : $perc < $second ? "#ffff55"
   : "#55ff55"
}

sub interact {
   my ($self, $pos) = @_;
   warn "INTERACT: @$pos\n";

   world_mutate_at ($pos, sub {
      my ($data) = @_;
      print "interact position [@$pos]: @$data\n";
      Games::Construder::Server::Objects::interact ($self, $data->[0], $pos);
      return 0;
   });
}

sub highlight {
   my ($self, $pos, $time, $color) = @_;
   $self->send_client ({
      cmd   => "highlight",
      pos   => $pos,
      color => $color,
      fade  => -$time
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
              [text => { color => "#888888", font => "small" }, "Look"],
              [text => { color => "#888888", font => "small" }, "Chunk"],
              [text => { color => "#888888", font => "small" }, "Sector"],
              [text => { color => "#888888", font => "small" }, "Type"],
           ],
           [box => { dir => "vert", padding => 2 },
              [text => { color => "#ffffff", font => "small" },
                 sprintf ("%3d,%3d,%3d", @$abs_pos)],
              [text => { color => "#ffffff", font => "small" },
                 sprintf ("%3d,%3d,%3d", @{vsmul ($self->{data}->{look_vec}, 10)})],
              [text => { color => "#ffffff", font => "small" },
                 sprintf ("%3d,%3d,%3d", @$chnk_pos)],
              [text => { color => "#ffffff", font => "small" },
                 sprintf ("%3d,%3d,%3d", @$sec_pos)],
              [text => { color => "#ffffff", font => "small" },
                 sprintf ("%s, %0.5f", $sinfo->{type}, $sinfo->{param})],
           ]
        ],
        [box => { },
           [text => { align => "right", font => "big", color => _range_color ($self->{data}->{happyness}, 90), max_chars => 4 },
              sprintf ("%d%%", $self->{data}->{happyness})],
           [text => { align => "center", color => "#888888" }, "happy"],
        ],
        [box => { },
           [text => { align => "right", font => "big", color => _range_color ($self->{data}->{bio}, 60), max_chars => 4 },
              sprintf ("%d%%", $self->{data}->{bio})],
           [text => { align => "center", color => "#888888" }, "bio"],
        ],
      ],
      commands => {
         need_selected_boxes => 1,
         default_keys => {
            f1 => "help",
            i  => "inventory",
            n  => "sector_finder",
            c  => "cheat",
            e  => "interact",
            f9 => "teleport_home",
            f12 => "exit_server",
         },
      },
   }, sub {
      my ($ui, $cmd, $arg, $pos) = @_;
      warn "CMD $pos | $arg\n";

      if ($cmd eq 'inventory') {
         $self->show_inventory;
      } elsif ($cmd eq 'sector_finder') {
         $self->show_sector_finder;
      } elsif ($cmd eq 'cheat') {
         $self->show_cheat_dialog;
      } elsif ($cmd eq 'help') {
         $self->show_help;
      } elsif ($cmd eq 'teleport_home') {
         $self->teleport ([0, 0, 0]);
      } elsif ($cmd eq 'interact') {
         $self->interact ($pos->[0]);
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
         $self->{data}->{slots}->{selected} = $i;
         $self->update_slots;
         $self->display_ui ('player_inv_sel');
      }
   });
}

sub show_cheat_dialog {
   my ($self) = @_;

   $self->display_ui (player_cheat => {
      window => { pos => [center => 'center'], },
      layout => [
         box => { dir => "vert", padding => 25 },
         [text => { align => 'center', font => 'big', color => "#00ff00" }, "Cheat"],
         [text => { align => 'center', font => 'normal', color => "#00ff00", wrap => 40 },
                  "What material do you want to max out in your inventory? Be careful, your score will be reset to 0!"],
         [box => {  dir => "hor" },
            [text => { font => 'normal', color => "#ffffff" }, "Material Type:"],
            [entry => { font => 'normal', color => "#ffffff", arg => "type",
                        highlight => ["#111111", "#333333"], max_chars => 9 },
             ""],
         ]
      ],
      commands => {
         default_keys => {
            return => "cheat",
         },
      },
   }, sub {
      if ($_[1] eq 'cheat') {
         my $t = $_[2]->{type};
         my ($spc, $max) = $self->inventory_space_for ($_[2]->{type});
         $self->{data}->{score} = 0;
         $self->update_score;
         $self->increase_inventory ($t, $spc);
         $self->display_ui ('player_cheat');
      }
   });

}

sub show_navigator {
   my ($self, @sec) = @_;

   if (@sec) {
      $self->{data}->{nav_to} = \@sec;
   } else {
      (@sec) = @{$self->{data}->{nav_to} || [0, 0, 0]};
   }

   my $chnk_pos = world_pos2chnkpos ($self->{data}->{pos});
   my $sec_pos  = world_chnkpos2secpos ($chnk_pos);
   my $dest_pos = \@sec;

   my $diff = vsub ($dest_pos, $sec_pos);

   my $alt =
      $diff->[1] > 0
         ? $diff->[1] . " above"
         : ($diff->[1] < 0
             ? (-$diff->[1]) . " below" : "same height");
   my $alt_ok = $diff->[1] == 0;

   my $lv = [@{$self->{data}->{look_vec}}];

   my $dist   = vlength ($diff);
   $lv->[1]   = 0;
   $diff->[1] = 0;
   my $dl     = vlength ($diff);
   my $l      = vlength ($lv) * $dl;

   my $r;
   my $dir_ok;
   if ($l > 0.001) {
      vinorm ($lv);
      vinorm ($diff);
      my $pdot = $lv->[0] * $diff->[2] - $lv->[2] * $diff->[0];
      $r = rad2deg (atan2 ($pdot, vdot ($lv, $diff)), 1);
      $r = int $r;
      $dir_ok = abs ($r) < 10;
      $r = $r < 0 ? -$r . "° left" : $r . "° right";
   } else {
      $r = 0;
      if ($dl <= 0.001) { # we arrived!
         $dir_ok = 1;
      }
   }

   $self->display_ui (player_nav => {
      window => {
         pos => ["right", "center"],
         sticky => 1,
         alpha => 0.6,
      },
      layout => [
         box => {
            dir => "vert",
         },
         [text => { font => "small", align => "center", color => "#888888" },
          "Navigator"],
         [box => {
            dir => "hor",
          },
          [box => { dir => "vert", padding => 4 },
             [text => { color => "#888888" }, "Pos"],
             [text => { color => "#888888" }, "Dest"],
             [text => { color => "#888888" }, "Dist"],
             [text => { color => "#888888" }, "Alt"],
             [text => { color => "#888888" }, "Dir"],
          ],
          [box => { dir => "vert", padding => 4 },
             [text => { color => "#888888" }, sprintf "%3d,%3d,%3d", @$sec_pos],
             [text => { color => "#888888" }, sprintf "%3d,%3d,%3d", @sec],
             [text => { color => "#ffffff" }, int ($dist)],
             [text => { color => $alt_ok ? "#00ff00" : "#ff0000" }, $alt],
             [text => { color => $dir_ok ? "#00ff00" : "#ff0000" }, $r],
          ],
         ],
      ],
      commands => {
         default_keys => {
            m => "close"
         }
      }
   }, sub { $_[1] eq "close" ? $self->display_ui ('player_nav') : () });
}

sub show_sector_finder {
   my ($self) = @_;

   my @sector_types =
      $Games::Construder::Server::RES->get_sector_types ();

   $self->display_ui (player_fsec => {
      window => {
         pos => [center => 'center'],
      },
      layout => [
         box => { dir => "vert" },
         [text => { font => "big", color => "#FFFFFF" }, "Navigator"],
         [text => { font => "small", color => "#888888" },
          "(Select a sector type with up/down keys and hit return.)"],
         [box => { },
         (map {
            [select_box => {
               dir => "vert", align => "center", arg => "item", tag => $_->[0],
               padding => 2,
               bgcolor => "#333333",
               border => { color => "#555555", width => 2 },
               select_border => { color => "#ffffff", width => 2 },
               aspect => 1
             }, [text => { font => "normal", color => "#ffffff" }, $_->[0]]
            ]
         } @sector_types)],
      ],
      commands => {
         default_keys => { return => "select", }
      }
   }, sub {
      warn "ARG: $_[2]->{item}|" . join (',', keys %{$_[2]}) . "\n";

      my $cmd = $_[1];
      warn "CMD $cmd\n";
      if ($cmd eq 'select') {
         my $item = $_[2]->{item};
         my ($s) = grep { $_->[0] eq $item } @sector_types;
         warn "ITEM @$s\n";
         my $chnk_pos = world_pos2chnkpos ($self->{data}->{pos});
         my $sec_pos  = world_chnkpos2secpos ($chnk_pos);
         my $coord =
            Games::Construder::Region::get_nearest_sector_in_range (
               $Games::Construder::Server::World::REGION,
               @$sec_pos,
               $s->[1], $s->[2],
            );

         if (@$coord) {
            my @coords;
            while (@$coord) {
               my $p = [shift @$coord, shift @$coord, shift @$coord];
               push @coords, $p;
            }
            (@coords) = map { $_->[3] = vlength (vsub ($sec_pos, $_)); $_ } @coords;
            (@coords) = sort { $a->[3] <=> $b->[3] } @coords;
            splice @coords, 15;

            $self->display_ui (player_fsec => {
               window => {
                  pos => [center => 'center'],
               },
               layout => [
                  box => { dir => "vert" },
                  [text => { color => "#ff0000", align => "center" },
                   "Sector with Type $item found at:\n"],
                  (map {
                     [select_box => {
                        dir => "vert", align => "left", arg => "item", tag => join (",",@$_),
                        padding => 2,
                        bgcolor => "#333333",
                        border => { color => "#555555", width => 2 },
                        select_border => { color => "#ffffff", width => 2 },
                      },
                      [
                         text => { font => "normal", color => "#ffffff" },
                         sprintf ("%d,%d,%d: %d", @$_)
                      ]
                     ]
                  } @coords)
               ],
               commands => { default_keys => { return => "select" } },
            }, sub {
               if ($_[1] eq 'select') {
                  warn "travel to $_[2]->{item}\n";
                  $self->display_ui ('player_fsec');
                  my (@vec) = split /,/, $_[2]->{item};
                  pop @vec; # remove distance
                  $self->show_navigator (@vec);
               }
            });

         } else {
            $self->display_ui (player_fsec => {
               window => {
                  pos => [center => 'center'],
               },
               layout => [
                  box => { dir => "vert" },
                  [text => { color => "#ff0000" },
                   "Sector with Type $item not found anywhere near!"]
               ]
            });
         }
      }
   });

#//AV *region_get_nearest_sector_in_range (void *reg, int x, int y, int z, double a, double b)

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
         my ($spc, $max) = $self->inventory_space_for ($i);
         push @row, [$i, $inv->{$i}, $o, shift @shortcuts, $max];
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
                     bgcolor => "#111111",
                     border => { color => "#555555", width => 2 },
                     select_border => { color => "#ffffff", width => 2 },
                     aspect => 1
                   },
                     [text => { align => "center", color => "#ffffff" },
                      $_->[1] ? $_->[1] . "/$_->[4]" : "0/0"],
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

sub debug_at {
   my ($self, $pos) = @_;
   world_mutate_at ($pos, sub {
      my ($data) = @_;
      print "position [@$pos]: @$data\n";
      if ($data->[0] == 1) {
         $data->[0] = 0;
         return 1;
      }
      return 0;
   });
}

sub do_materialize {
   my ($self, $pos, $type, $time, $energy, $score) = @_;

   my $id = world_pos2id ($pos);

   $self->highlight ($pos, $time, [0, 1, 0]);

   $self->push_tick_change (bio => -$energy);

   $self->{materializings}->{$id} = 1;
   my $tmr;
   $tmr = AE::timer $time, 0, sub {
      world_mutate_at ($pos, sub {
         my ($data) = @_;
         $data->[0] = $type;
        #d# $data->[3] = 0x2;
         $self->push_tick_change (score => $score);
         delete $self->{materializings}->{$id};
         undef $tmr;
         return 1;
      });
   };
}

sub start_materialize {
   my ($self, $pos) = @_;

   my $id = world_pos2id ($pos);
   if ($self->{materializings}->{$id}) {
      return;
   }

   # has item?
   # enough bio energy?
   # space to build is free?
   # => decrease inventory item
   # => init materialize
   #   after sucess => calculate score points

   my $type = $self->{data}->{slots}->{selection}->[$self->{data}->{slots}->{selected}];

   world_mutate_at ($pos, sub {
      my ($data) = @_;

      return 0 unless $data->[0] == 0;

      return 0 unless $self->decrease_inventory ($type);

      my $obj = $Games::Construder::Server::RES->get_object_by_type ($type);
      my ($time, $energy, $score) =
         $Games::Construder::Server::RES->get_type_materialize_values ($type);
      unless ($self->{data}->{bio} >= $energy) {
         $self->msg (1, "You don't have enough energy to materialize the $obj->{name}!");
         return;
      }

      $data->[0] = 1;
      $self->do_materialize ($pos, $type, $time, $energy, $score);
      return 1;
   }, no_light => 1);
}

sub inventory_space_for {
   my ($self, $type) = @_;
   my $spc = $Games::Construder::Server::RES->get_type_inventory_space ($type);
   my $cnt;
   if (exists $self->{data}->{inv}->{$type}) {
      $cnt = $self->{data}->{inv}->{$type};
   } else {
      if (scalar (grep { $_ ne '' && $_ != 0 } keys %{$self->{data}->{inv}}) >= $PL_MAX_INV) {
         $cnt = $spc;
      }
   }

   my $dlta = $spc - $cnt;

   ($dlta < 0 ? 0 : $dlta, $spc)
}

sub do_dematerialize {
   my ($self, $pos, $type, $time, $energy) = @_;

   my $id = world_pos2id ($pos);
   $self->highlight ($pos, $time, [1, 0, 0]);

   $self->push_tick_change (bio => -$energy);

   $self->{dematerializings}->{$id} = 1;
   my $tmr;
   $tmr = AE::timer $time, 0, sub {
      world_mutate_at ($pos, sub {
         my ($data) = @_;
         warn "INCREATE $type\n";
         $self->increase_inventory ($type);
         $data->[0] = 0;
         $data->[3] &= 0xF0; # clear color :)
         delete $self->{dematerializings}->{$id};
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

   world_mutate_at ($pos, sub {
      my ($data) = @_;
      my $type = $data->[0];
      my $obj = $Games::Construder::Server::RES->get_object_by_type ($type);
      if ($obj->{untransformable}) {
         return;
      }
      warn "DEMAT $type\n";

      unless ($self->has_inventory_space ($type)) {
         $self->msg (1, "Inventory full, no space for $obj->{name} available!");
         return;
      }

      my ($time, $energy) =
         $Games::Construder::Server::RES->get_type_dematerialize_values ($type);
      unless ($obj->{bio_energy} || $self->{data}->{bio} >= $energy) {
         $self->msg (1, "You don't have enough energy to dematerialize the $obj->{name}!");
         return;
      }

      $data->[0] = 1; # materialization!
      $self->do_dematerialize ($pos, $type, $time, $energy);

      return 1;
   }, no_light => 1);

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
   my ($self, $ui, $cmd, $arg, $pos) = @_;
   warn "ui response $ui: $cmd ($arg) (@$pos)\n";

   if (my $u = $self->{displayed_uis}->{$ui}) {
      $u->($ui, $cmd, $arg, $pos);
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
