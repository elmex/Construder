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
my $PL_MAX_INV = 28;

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
   my $tick_time = time;
   $self->{tick_timer} = AE::timer 0.25, 0.25, sub {
      my $cur = time;
      $wself->player_tick ($cur - $tick_time);
      $tick_time = $cur;
   };

   $self->{logic}->{unhappy_rate} = 0.25; # 0.25% per second

   $self->new_ui (bio_warning => "Games::Construder::Server::UI::BioWarning");
   $self->new_ui (msgbox      => "Games::Construder::Server::UI::MsgBox");
   $self->new_ui (score       => "Games::Construder::Server::UI::Score");
   $self->new_ui (slots       => "Games::Construder::Server::UI::Slots");
   $self->new_ui (status      => "Games::Construder::Server::UI::Status");
   $self->new_ui (material_view => "Games::Construder::Server::UI::MaterialView");
   $self->new_ui (inventory   => "Games::Construder::Server::UI::Inventory");

   $self->update_score;
   $self->{uis}->{slots}->show;
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

   my $bio_ui = $self->{uis}->{bio_warning};

   if ($starves) {
      unless ($self->{death_timer}) {
         my $cnt = 30;
         $self->{death_timer} = AE::timer 0, 1, sub {
            if ($cnt-- <= 0) {
               $self->kill_player;
               delete $self->{death_timer};

               $bio_ui->hide;
            } else {
               $bio_ui->show ($cnt);
            }
         };
      }

   } else {
      if (delete $self->{death_timer}) {
         $bio_ui->hide;
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
         $self->{uis}->{inventory}->show; # update if neccesary
      }

      $self->{uis}->{slots}->show;

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
      $self->{uis}->{inventory}->show; # update if neccesary
   }

   $self->{uis}->{slots}->show;

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

sub logout {
   my ($self) = @_;
   $self->save;
   delete $self->{uis};
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

sub get_pos_normalized {
   my ($self) = @_;
   vfloor ($self->{data}->{pos})
}

sub get_pos_chnk {
   my ($self) = @_;
   world_pos2chnkpos ($self->{data}->{pos})
}

sub get_pos_sector {
   my ($self) = @_;
   world_chnkpos2secpos (world_pos2chnkpos ($self->{data}->{pos}))
}

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
   $self->{uis}->{msgbox}->show ($error, $msg);
}

sub update_score {
   my ($self, $hl) = @_;
   $self->{uis}->{score}->show ($hl);
}

# TODO: Continue here with UI rewrite:

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

sub show_cheat_dialog {
   my ($self) = @_;

   #R# $self->display_ui (player_cheat => {
   #R#    window => { pos => [center => 'center'], },
   #R#    layout => [
   #R#       box => { dir => "vert", padding => 25 },
   #R#       [text => { align => 'center', font => 'big', color => "#00ff00" }, "Cheat"],
   #R#       [text => { align => 'center', font => 'normal', color => "#00ff00", wrap => 40 },
   #R#                "What material do you want to max out in your inventory? Be careful, your score will be reset to 0!"],
   #R#       [box => {  dir => "hor" },
   #R#          [text => { font => 'normal', color => "#ffffff" }, "Material Type:"],
   #R#          [entry => { font => 'normal', color => "#ffffff", arg => "type",
   #R#                      highlight => ["#111111", "#333333"], max_chars => 9 },
   #R#           ""],
   #R#       ]
   #R#    ],
   #R#    commands => {
   #R#       default_keys => {
   #R#          return => "cheat",
   #R#       },
   #R#    },
   #R# }, sub {
   #R#    if ($_[1] eq 'cheat') {
   #R#       my $t = $_[2]->{type};
   #R#       my ($spc, $max) = $self->inventory_space_for ($_[2]->{type});
   #R#       $self->{data}->{score} = 0;
   #R#       $self->update_score;
   #R#       $self->increase_inventory ($t, $spc);
   #R#       $self->display_ui ('player_cheat');
   #R#    }
   #R# });

}

sub show_location_book {
   my ($self) = @_;

   #R#ui_player_location_book ($pl, sub {
   #R#   map { [$_, $self->{data}->{tags}] } 0..9
   #R#}, sub {
   #R#   my ($slot, $name) = @_;
   #R#   $self->{data}->{tags}->[$slot] = $name, $chnk_pos, $sec_pos;
   #R#});
}

sub show_navigator {
   my ($self, @sec) = @_;

   #R# if (@sec) {
   #R#    $self->{data}->{nav_to} = \@sec;
   #R# } else {
   #R#    (@sec) = @{$self->{data}->{nav_to} || [0, 0, 0]};
   #R# }

   #R# my $chnk_pos = world_pos2chnkpos ($self->{data}->{pos});
   #R# my $sec_pos  = world_chnkpos2secpos ($chnk_pos);
   #R# my $dest_pos = \@sec;

   #R# my $diff = vsub ($dest_pos, $sec_pos);

   #R# my $alt =
   #R#    $diff->[1] > 0
   #R#       ? $diff->[1] . " above"
   #R#       : ($diff->[1] < 0
   #R#           ? (-$diff->[1]) . " below" : "same height");
   #R# my $alt_ok = $diff->[1] == 0;

   #R# my $lv = [@{$self->{data}->{look_vec}}];

   #R# my $dist   = vlength ($diff);
   #R# $lv->[1]   = 0;
   #R# $diff->[1] = 0;
   #R# my $dl     = vlength ($diff);
   #R# my $l      = vlength ($lv) * $dl;

   #R# my $r;
   #R# my $dir_ok;
   #R# if ($l > 0.001) {
   #R#    vinorm ($lv);
   #R#    vinorm ($diff);
   #R#    my $pdot = $lv->[0] * $diff->[2] - $lv->[2] * $diff->[0];
   #R#    $r = rad2deg (atan2 ($pdot, vdot ($lv, $diff)), 1);
   #R#    $r = int $r;
   #R#    $dir_ok = abs ($r) < 10;
   #R#    $r = $r < 0 ? -$r . "° left" : $r . "° right";
   #R# } else {
   #R#    $r = 0;
   #R#    if ($dl <= 0.001) { # we arrived!
   #R#       $dir_ok = 1;
   #R#    }
   #R# }

   #R# $self->display_ui (player_nav => {
   #R#    window => {
   #R#       pos => ["right", "center"],
   #R#       sticky => 1,
   #R#       alpha => 0.6,
   #R#    },
   #R#    layout => [
   #R#       box => {
   #R#          dir => "vert",
   #R#       },
   #R#       [text => { font => "small", align => "center", color => "#888888" },
   #R#        "Navigator"],
   #R#       [box => {
   #R#          dir => "hor",
   #R#        },
   #R#        [box => { dir => "vert", padding => 4 },
   #R#           [text => { color => "#888888" }, "Pos"],
   #R#           [text => { color => "#888888" }, "Dest"],
   #R#           [text => { color => "#888888" }, "Dist"],
   #R#           [text => { color => "#888888" }, "Alt"],
   #R#           [text => { color => "#888888" }, "Dir"],
   #R#        ],
   #R#        [box => { dir => "vert", padding => 4 },
   #R#           [text => { color => "#888888" }, sprintf "%3d,%3d,%3d", @$sec_pos],
   #R#           [text => { color => "#888888" }, sprintf "%3d,%3d,%3d", @sec],
   #R#           [text => { color => "#ffffff" }, int ($dist)],
   #R#           [text => { color => $alt_ok ? "#00ff00" : "#ff0000" }, $alt],
   #R#           [text => { color => $dir_ok ? "#00ff00" : "#ff0000" }, $r],
   #R#        ],
   #R#       ],
   #R#    ],
   #R#    commands => {
   #R#       default_keys => {
   #R#          m => "close"
   #R#       }
   #R#    }
   #R# }, sub { $_[1] eq "close" ? $self->display_ui ('player_nav') : () });
}

sub show_sector_finder {
   my ($self) = @_;

   #R# my @sector_types =
   #R#    $Games::Construder::Server::RES->get_sector_types ();

   #R# $self->display_ui (player_fsec => {
   #R#    window => {
   #R#       pos => [center => 'center'],
   #R#    },
   #R#    layout => [
   #R#       box => { dir => "vert" },
   #R#       [text => { font => "big", color => "#FFFFFF" }, "Navigator"],
   #R#       [text => { font => "small", color => "#888888" },
   #R#        "(Select a sector type with up/down keys and hit return.)"],
   #R#       [box => { },
   #R#       (map {
   #R#          [select_box => {
   #R#             dir => "vert", align => "center", arg => "item", tag => $_->[0],
   #R#             padding => 2,
   #R#             bgcolor => "#333333",
   #R#             border => { color => "#555555", width => 2 },
   #R#             select_border => { color => "#ffffff", width => 2 },
   #R#             aspect => 1
   #R#           }, [text => { font => "normal", color => "#ffffff" }, $_->[0]]
   #R#          ]
   #R#       } @sector_types)],
   #R#    ],
   #R#    commands => {
   #R#       default_keys => { return => "select", }
   #R#    }
   #R# }, sub {
   #R#    warn "ARG: $_[2]->{item}|" . join (',', keys %{$_[2]}) . "\n";

   #R#    my $cmd = $_[1];
   #R#    warn "CMD $cmd\n";
   #R#    if ($cmd eq 'select') {
   #R#       my $item = $_[2]->{item};
   #R#       my ($s) = grep { $_->[0] eq $item } @sector_types;
   #R#       warn "ITEM @$s\n";
   #R#       my $chnk_pos = world_pos2chnkpos ($self->{data}->{pos});
   #R#       my $sec_pos  = world_chnkpos2secpos ($chnk_pos);
   #R#       my $coord =
   #R#          Games::Construder::Region::get_nearest_sector_in_range (
   #R#             $Games::Construder::Server::World::REGION,
   #R#             @$sec_pos,
   #R#             $s->[1], $s->[2],
   #R#          );

   #R#       if (@$coord) {
   #R#          my @coords;
   #R#          while (@$coord) {
   #R#             my $p = [shift @$coord, shift @$coord, shift @$coord];
   #R#             push @coords, $p;
   #R#          }
   #R#          (@coords) = map { $_->[3] = vlength (vsub ($sec_pos, $_)); $_ } @coords;
   #R#          (@coords) = sort { $a->[3] <=> $b->[3] } @coords;
   #R#          splice @coords, 15;

   #R#          $self->display_ui (player_fsec => {
   #R#             window => {
   #R#                pos => [center => 'center'],
   #R#             },
   #R#             layout => [
   #R#                box => { dir => "vert" },
   #R#                [text => { color => "#ff0000", align => "center" },
   #R#                 "Sector with Type $item found at:\n"],
   #R#                (map {
   #R#                   [select_box => {
   #R#                      dir => "vert", align => "left", arg => "item", tag => join (",",@$_),
   #R#                      padding => 2,
   #R#                      bgcolor => "#333333",
   #R#                      border => { color => "#555555", width => 2 },
   #R#                      select_border => { color => "#ffffff", width => 2 },
   #R#                    },
   #R#                    [
   #R#                       text => { font => "normal", color => "#ffffff" },
   #R#                       sprintf ("%d,%d,%d: %d", @$_)
   #R#                    ]
   #R#                   ]
   #R#                } @coords)
   #R#             ],
   #R#             commands => { default_keys => { return => "select" } },
   #R#          }, sub {
   #R#             if ($_[1] eq 'select') {
   #R#                warn "travel to $_[2]->{item}\n";
   #R#                $self->display_ui ('player_fsec');
   #R#                my (@vec) = split /,/, $_[2]->{item};
   #R#                pop @vec; # remove distance
   #R#                $self->show_navigator (@vec);
   #R#             }
   #R#          });

   #R#       } else {
   #R#          $self->display_ui (player_fsec => {
   #R#             window => {
   #R#                pos => [center => 'center'],
   #R#             },
   #R#             layout => [
   #R#                box => { dir => "vert" },
   #R#                [text => { color => "#ff0000" },
   #R#                 "Sector with Type $item not found anywhere near!"]
   #R#             ]
   #R#          });
   #R#       }
   #R#    }
   #R# });

#//AV *region_get_nearest_sector_in_range (void *reg, int x, int y, int z, double a, double b)

}

sub show_help {
   my ($self) = @_;
   return;

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

sub new_ui {
   my ($self, $id, $class, %arg) = @_;
   my $o = $class->new (ui_name => $id, pl => $self, %arg);
   $self->{uis}->{$id} = $o;
}

sub delete_ui {
   my ($self, $id) = @_;
   delete $self->{uis}->{$id};
}

sub display_ui {
   my ($self, $id, $dest) = @_;

   my $o = $self->{uis}->{$id};

   unless ($dest) {
      $self->send_client ({ cmd => deactivate_ui => ui => $id });
      delete $o->{shown};
      return;
   }

   $self->send_client ({ cmd => activate_ui => ui => $id, desc => $dest });
   $o->{shown} = 1;
}

sub ui_res : event_cb {
   my ($self, $ui, $cmd, $arg, $pos) = @_;
   warn "ui response $ui: $cmd ($arg) (@$pos)\n";

   if (my $o = $self->{uis}->{$ui}) {
      $o->react ($cmd, $arg, $pos);

      delete $o->{shown}
         if $cmd eq 'cancel';
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
