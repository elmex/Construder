package Games::Construder::Server::UI;
use common::sense;
use Scalar::Util qw/weaken/;
require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   ui_player_score
   ui_player_bio_warning
   ui_player_tagger
/;

=head1 NAME

Games::Construder::Server::UI - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   weaken $self->{pl};

   $self->init;

   return $self
}

sub init {
}

sub layout {
   my ($self, @args) = @_;
   die "subclass responsibility\n";
}

sub commands { # subclasses should overwrite this
   my ($self) = @_;
   # key => cmd name
   ()
}

sub new_ui {
   my ($self, @args) = @_;
   $self->{pl}->new_ui (@args);
}

sub show_ui {
   my ($self, $name, @arg) = @_;
   $self->{pl}->{uis}->{$name}->show (@arg);
}

sub delete_ui {
   my ($self, @args) = @_;
   $self->{pl}->delete_ui (@args);
}

sub update {
   my ($self, @args) = @_;
   $self->show (@args) if $self->{shown};
}

sub show {
   my ($self, @args) = @_;
   my $lyout = $self->layout (@args);
   $lyout->{commands}->{default_keys} = { $self->commands };
   if ($self->{cmd_need_select_boxes}) {
      $lyout->{commands}->{need_selected_boxes} = 1;
   }
   $self->{pl}->display_ui ($self->{ui_name} => $lyout);
}

sub handle_command { # subclasses should overwrite this
}

sub react {
   my ($self, $cmd, $arg, $pos) = @_;
   return unless $self->{shown};

   $self->handle_command ($cmd, $arg, $pos);
}

sub hide {
   my ($self) = @_;
   $self->{pl}->display_ui ($self->{ui_name});
}

sub DESTROY {
   my ($self) = @_;
   $self->{pl}->display_ui ($self->{ui_name});
}

package Games::Construder::Server::UI::Score;

use base qw/Games::Construder::Server::UI/;

sub layout {
   my ($self, $hl) = @_;

   if ($hl) {
      my $wself = $self;
      weaken $wself;
      $self->{upd_score_hl_tmout} = AE::timer 1.5, 0, sub {
         $wself->show;
         delete $wself->{upd_score_hl_tmout};
      };
   }

   my $score =  $self->{pl}->{data}->{score};

   {
      window => {
         sticky  => 1,
         pos     => [center => "up"],
         alpha   => $hl ? 1 : 0.6,
      },
      layout => [
         box => {
            border  => { color => $hl ? "#ff0000" : "#777700" },
            padding => ($hl ? 10 : 2),
            align   => "hor",
         },
         [text => {
            font  => "normal",
            color => "#aa8800",
            align => "center"
          }, "Score:"],
         [text => {
            font  => "big",
            color => $hl ? "#ff0000" : "#aa8800",
          }, ($score . ($hl ? "+$hl" : ""))]
      ]
   }
}

package Games::Construder::Server::UI::BioWarning;

use base qw/Games::Construder::Server::UI/;

sub layout {
   my ($self, $seconds) = @_;

   {
      window => {
         sticky => 1,
         pos    => [center => 'center', 0, -0.15],
         alpha  => 0.3,
      },
      layout => [
         box => { dir => "vert" },
         [text => { font => "big", color => "#ff0000", wrap => 28, align => "center" },
          "Warning: Bio energy level low! You have $seconds seconds left!\n"],
         [text => { font => "normal", color => "#ff0000", wrap => 35, align => "center" },
          "Death imminent, please dematerialize something that provides bio energy!"],
      ]
   }
}

package Games::Construder::Server::UI::MsgBox;

use base qw/Games::Construder::Server::UI/;

sub layout {
   my ($self, $error, $msg) = @_;

   my $wself = $self;
   weaken $wself;
   $self->{msg_tout} = AE::timer (($error ? 4 : 2.5), 0, sub {
      $wself->hide;
      delete $wself->{msg_tout};
   });

   {
      window => {
         pos => [center => "center", 0, 0.25],
         alpha => 0.6,
      },
      layout => [
         text => { font => "big", color => $error ? "#ff0000" : "#ffffff", wrap => 20 },
         $msg
      ]
   }
}

package Games::Construder::Server::UI::Slots;

use base qw/Games::Construder::Server::UI/;

sub commands {
   (
      map {
         $_ => "slot_" . ($_ == 0 ? 9 : $_ - 1)
      } 0..9
   )
}

sub handle_command {
   my ($self, $cmd, $arg, $pos) = @_;

   warn "CMD @_\n";

   if ($cmd =~ /slot_(\d+)/) {
      $self->{pl}->{data}->{slots}->{selected} = $1;
      $self->show;
   }
}

sub layout {
   my ($self) = @_;

   my $slots = $self->{pl}->{data}->{slots};
   my $inv   = $self->{pl}->{data}->{inv};

   my @slots;
   for (my $i = 0; $i < 10; $i++) {
      my $cur = $slots->{selection}->[$i];

      my $border = "#0000ff";
      if ($i == $slots->{selected}) {
         $border = "#ff0000";
      }

      my $o = $Games::Construder::Server::RES->get_object_by_type ($cur);
      my ($spc, $max) = $self->{pl}->inventory_space_for ($cur);

      push @slots,
      [box => { padding => 2, aspect => 1 },
      [box => { dir => "vert", padding => 2, border => { color => $border }, aspect => 1 },
         [box => { padding => 2, align => "center" },
           [model => { color => "#00ff00", width => 40 }, $cur]],
         [text => { font => "small", color => $cur && $inv->{$cur} <= 0 ? "#990000" : "#999999", align => "center" },
          sprintf ("[%d] %d/%d", $i + 1, $inv->{$cur} * 1, $cur ? $max : 0)]
      ]];
   }

   {
      window => {
         sticky => 1,
         pos    => [left => "down"],
      },
      layout => [
         box => { }, @slots
      ],
   }
}

package Games::Construder::Server::UI::Status;
use Games::Construder::Server::World;

use base qw/Games::Construder::Server::UI/;

sub init {
   my ($self) = @_;

   my $wself = $self;
   weaken $wself;
   $self->{tmr} = AE::timer 0, 1, sub {
      $wself->show;
   };
}

sub commands {
   my ($self) = @_;
   $self->{cmd_need_select_boxes} = 1;

   (
      f1  => "help",
      f9  => "teleport_home",
      f12 => "exit_server",
      i   => "inventory",
      n   => "sector_finder",
      c   => "cheat",
      x   => "assignment",
      t   => "location_book",
      e   => "interact",
      q   => "query",
   )
}

sub handle_command {
   my ($self, $cmd, $arg, $pos) = @_;

   my $pl = $self->{pl};

   if ($cmd eq 'inventory') {
      $self->show_ui ('inventory');
   } elsif ($cmd eq 'location_book') {
      $pl->show_location_book;
   } elsif ($cmd eq 'sector_finder') {
      $self->show_ui ('sector_finder');
   } elsif ($cmd eq 'cheat') {
      $self->show_ui ('cheat');
   } elsif ($cmd eq 'help') {
      $pl->show_help;
   } elsif ($cmd eq 'teleport_home') {
      $pl->teleport ([0, 0, 0]);
   } elsif ($cmd eq 'interact') {
      $pl->interact ($pos->[0]) if @{$pos->[0] || []};
   } elsif ($cmd eq 'query') {
      $pl->query ($pos->[0]);
   } elsif ($cmd eq 'assignment') {
      $self->show_ui ('assignment');
   } elsif ($cmd eq 'exit_server') {
      exit;
   }
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

sub layout {
   my ($self) = @_;

   my $abs_pos  = $self->{pl}->get_pos_normalized;
   my $chnk_pos = $self->{pl}->get_pos_chnk;
   my $sec_pos  = $self->{pl}->get_pos_sector;

   my $sinfo = world_sector_info (@$chnk_pos);

   {
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
              #d#[text => { color => "#888888", font => "small" }, "Look"],
              [text => { color => "#888888", font => "small" }, "Chunk"],
              [text => { color => "#888888", font => "small" }, "Sector"],
              [text => { color => "#888888", font => "small" }, "Type"],
           ],
           [box => { dir => "vert", padding => 2 },
              [text => { color => "#ffffff", font => "small" },
                 sprintf ("%3d,%3d,%3d", @$abs_pos)],
              #d#[text => { color => "#ffffff", font => "small" },
              #d#   sprintf ("%3d,%3d,%3d", @{vsmul ($self->{data}->{look_vec}, 10)})],
              [text => { color => "#ffffff", font => "small" },
                 sprintf ("%3d,%3d,%3d", @$chnk_pos)],
              [text => { color => "#ffffff", font => "small" },
                 sprintf ("%3d,%3d,%3d", @$sec_pos)],
              [text => { color => "#ffffff", font => "small" },
                 sprintf ("%s, %0.5f", $sinfo->{type}, $sinfo->{param})],
           ]
        ],
        [box => { },
           [text => { align => "right", font => "big", color => _range_color ($self->{pl}->{data}->{happyness}, 90), max_chars => 4 },
              sprintf ("%d%%", $self->{pl}->{data}->{happyness})],
           [text => { align => "center", color => "#888888" }, "happy"],
        ],
        [box => { },
           [text => { align => "right", font => "big", color => _range_color ($self->{pl}->{data}->{bio}, 60), max_chars => 4 },
              sprintf ("%d%%", $self->{pl}->{data}->{bio})],
           [text => { align => "center", color => "#888888" }, "bio"],
        ],
      ],
   }
}

package Games::Construder::Server::UI::CountQuery;

use base qw/Games::Construder::Server::UI/;

sub init {
}

sub commands {
   (
      return => "enter"
   )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;
   my $max_cnt = $self->{max_count};

   if ($cmd eq 'enter') {
      my $cnt = $arg->{cnt};
      if ($cnt <= $max_cnt) {
         $self->{cb}->($cnt);

      } else {
         $self->show ('error');
      }

   } elsif ($cmd eq 'cancel') {
      $self->{cb}->();
   }
}

sub layout {
   my ($self, $error) = @_;

   my $msg = $self->{msg};

   {
      window => {
         pos => [center => 'center'],
      },
      layout => [
         box => { dir => "vert" },
         [text => { color => "#ffffff", align => "center" },
          $msg],
         ($error ?
            [text => { align => "center", color => "#ff0000" },
             "Entered value: $error, is too high!"] : ()),
         [box => { dir => "hor", align => "center" },
            [entry => { font => 'normal', color => "#ffffff", arg => "cnt",
                        highlight => ["#111111", "#333333"], max_chars => 3 },
             $self->{max_count}],
            [text => { font => "normal", color => "#999999" }, "Max: $self->{max_count}"]],
      ]
   }
}

package Games::Construder::Server::UI::MaterialView;

use base qw/Games::Construder::Server::UI/;

sub commands {
   my ($self) = @_;

   my $type = $self->{type};

   my $inv_cnt = $self->{pl}->{data}->{inv}->{$type}
      or return ();
   (
      (map {
         $_ => "slot_" . ($_ == 0 ? 9 : $_ - 1)
      } 0..9),
      d => "discard",
   )
}

my %PERC = (
   10 => "extremely low",
   20 => "very low",
   30 => "low",
   50 => "medium",
   70 => "high",
   80 => "very high",
   90 => "extremely high",
);

sub _perc_to_word {
   my ($p) = @_;

   my (@k) = sort keys %PERC;
   my $k = shift @k;
   while ($p > $k) {
      $k = shift @k;
   }

   $PERC{$k}
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   my $type = $self->{type};
   warn "HAD $cmd\n";

   if ($cmd =~ /slot_(\d+)/) {
      $self->{pl}->{data}->{slots}->{selection}->[$1] = $type;
      $self->{pl}->{data}->{slots}->{selected} = $1;
      $self->show_ui ('slots');
      $self->hide;

   } elsif ($cmd eq 'discard') {
      $self->hide;
      warn "DISC $self->{pl}->{data}->{inv}->{$self->{type}}\n";
      $self->new_ui (discard_material =>
         "Games::Construder::Server::UI::CountQuery",
         msg       => "Discard how many?",
         max_count => $self->{pl}->{data}->{inv}->{$self->{type}},
         cb => sub {
            if (defined $_[0]) {
               $self->{pl}->decrease_inventory ($self->{type}, $_[0]);
            }
            $self->delete_ui ('discard_material');
         });
      $self->show_ui ('discard_material');
   }
}

sub layout {
   my ($self, $type) = @_;

   $self->{type} = $type;

   my $inv_cnt = $self->{pl}->{data}->{inv}->{$type};

   warn "SHOW INV SEL $type\n";
   my $o = $Games::Construder::Server::RES->get_object_by_type ($type);

   my @sec =
      $Games::Construder::Server::RES->get_sector_types_where_type_is_found ($type);

   my @destmat =
      $Games::Construder::Server::RES->get_types_where_type_is_source_material ($type);

   my @srcmat =
      $Games::Construder::Server::RES->get_type_source_materials ($type);
      warn "RET\n";


   {
      window => {
         pos => [center => 'center'],
      },
      layout => [
         box => { dir => "vert" },
          [text => { color => "#ffffff", font => "big" }, $o->{name}],
          [box => { dir => "hor", align => "left" },
             [text => { align => "left", color => "#ffffff", font => "normal", wrap => 35 }, $o->{lore}],
             [model => { align => "left", animated => 0, width => 90 }, $o->{type}],
             (@srcmat
               ? [box => { dir => "vert", align => "left" },
                  [text => { color => "#999999", font => "small", align => "center" },
                   "Build Pattern:\n"
                   . join ("\n", map { $_->[1] . "x " . $_->[0]->{name} } @srcmat)],
                  [model => { animated => 1, width => 90, align => "center" }, $o->{type}],
                 ]
               : ()),
          ],
          [text => { color => "#9999ff", font => "normal", wrap => 50 },
             "- It's complexity is " . _perc_to_word ($o->{complexity}) .
             " and it's density is " . _perc_to_word ($o->{density})],
          [text => { color => "#9999ff", font => "normal", wrap => 50 },
            @sec
               ? "- This can be found in sectors with following types: "
                    . join (", ", @sec)
               : "- This can not be found in any sector."],
          [text => { color => "#9999ff", font => "normal", wrap => 50 },
           (@destmat
              ? "- This can be used as source material for: "
                . join (", ", map { $_->{name} } @destmat)
              : "- This can't be processed any further.")],
          $inv_cnt ? (
             [text => { color => "#9999ff", font => "normal", wrap => 50 },
                "- You have $inv_cnt of this in your inventory."],
             [text => { color => "#0000ff" }, "Possible Actions:"],
             [box => { dir => "vert", padding => 10, border => { color => "#0000ff" } },
                [text => { color => "#ffffff", font => "normal", wrap => 50 },
                   "* Assign to slot, press keys '0' to '9'"],
                [text => { color => "#ffffff", font => "normal", wrap => 50 },
                   "* Discard some, press key 'd'"],
             ]
          ) : ()
      ],
   }
}


package Games::Construder::Server::UI::Inventory;

use base qw/Games::Construder::Server::UI/;

sub build_grid {
   my ($self) = @_;

   my $inv = $self->{pl}->{data}->{inv};

   my @grid;

   my @keys = sort { $a <=> $b } keys %$inv;
   my @shortcuts = qw/
      1 q a y 2 w s x
      3 e d c 4 r f v
      5 t g b 6 z h n
      7 u j m 8 i k ,
   /;

   for (0..6) {
      my @row;
      for (0..3) {
         my $i = (shift @keys) || 1;
         my $o = $Games::Construder::Server::RES->get_object_by_type ($i);
         my ($spc, $max) = $self->{pl}->inventory_space_for ($i);
                    # type, inv count, max inv, object info, shortcut
         push @row, [$i, $inv->{$i}, $max, $o, shift @shortcuts];
      }
      push @grid, \@row;
   }

   $self->{grid} = \@grid;
}

sub commands {
   my ($self) = @_;
   my $grid = $self->{grid};

   (
      return => "select",
      map { $_->[4] => "short_" . $_->[0] }
         map { @$_ } @$grid
   )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'select') {
      $self->hide;
      $self->show_ui ('material_view', $arg->{item}->[0]);

   } elsif ($cmd =~ /short_(\d+)/) {
      $self->hide;
      $self->show_ui ('material_view', $1);
   }
}

sub layout {
   my ($self) = @_;

   $self->build_grid;

   {
      window => {
         pos => [center => 'center'],
      },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" } },
         [text => { font => "big", color => "#FFFFFF", align => "center" }, "Inventory"],
         [text => { font => "small", color => "#888888", wrap => 40, align => "center" },
          "(Select a resource directly by [shortcut key] or up/down and hit return.)"],
         [box => { },
            (map {
               [box => { dir => "vert", padding => 4 },
                  map {
                     [select_box => {
                        dir => "vert", align => "center", arg => "item", tag => $_,
                        padding => 2,
                        bgcolor => "#111111",
                        border => { color => "#000000", width => 2 },
                        select_border => { color => "#ffffff", width => 2 },
                        aspect => 1
                      },
                        [text => { align => "center", color => "#ffffff" },
                         $_->[1] ? $_->[1] . "/$_->[2]" : "0/0"],
                        [model => { align => "center", width => 60 }, $_->[0]],
                        [text  => { font => "small", align => "center",
                                    color => "#ffffff" },
                         $_->[0] == 1 ? "<empty>" : "[$_->[4]] $_->[3]->{name}"]
                     ]

                  } @$_
               ]
            } @{$self->{grid}})
         ]
      ],
   }
}

package Games::Construder::Server::UI::Cheat;

use base qw/Games::Construder::Server::UI/;

sub commands {
   ( return => "cheat" )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'cheat') {

      my $t = $arg->{type};
      my ($spc, $max) = $self->{pl}->inventory_space_for ($arg->{type});
      $self->{pl}->{data}->{score} = 0;
      $self->{pl}->update_score;
      $self->{pl}->increase_inventory ($t, $spc);
      $self->hide;
   }
}

sub layout {
   {
      window => { pos => [center => 'center'], },
      layout => [
         box => { dir => "vert", padding => 25, border => { color => "#ffffff" } },
         [text => { align => 'center', font => 'big', color => "#00ff00" }, "Cheat"],
         [text => { align => 'center', font => 'normal', color => "#00ff00", wrap => 40 },
                  "What material do you want to max out in your inventory? Be careful, your score will be reset to 0!"],
         [box => {  dir => "hor", align => "center" },
            [text => { font => 'normal', color => "#ffffff" }, "Material Type:"],
            [entry => { font => 'normal', color => "#ffffff", arg => "type",
                        highlight => ["#111111", "#333333"], max_chars => 9 },
             ""],
         ]
      ]
   }
}

package Games::Construder::Server::UI::Navigator;
use Games::Construder::Vector;
use Math::Trig qw/deg2rad rad2deg pi tan atan/;

use base qw/Games::Construder::Server::UI/;

sub commands {
   ( m => "close" )
}

sub handle_command {
   my ($self, $cmd) = @_;
   if ($cmd eq 'close') {
      $self->hide;
   }
}

sub layout {
   my ($self, $type, $pos) = @_;

   if ($type eq 'pos') {
      $self->layout_pos ($pos);
   } elsif ($type eq 'sector') {
      $self->layout_sector ($pos);
   } elsif ($self->{nav_to_sector}) {
      $self->layout_sector ();
   } else {
      $self->layout_pos ();
   }

}

sub layout_pos {
   my ($self, $pos) = @_;

   if ($pos) {
      $self->{nav_to_pos} = $pos;
   } else {
      ($pos) = $self->{nav_to_pos} || [0, 0, 0];
   }

   my $sec_pos  = $self->{pl}->get_pos_normalized;
   my $dest_pos = [@$pos];

   my $diff = vsub ($dest_pos, $sec_pos);

   my $alt =
      $diff->[1] > 0
         ? $diff->[1] . " above"
         : ($diff->[1] < 0
             ? (-$diff->[1]) . " below" : "same height");
   my $alt_ok = $diff->[1] == 0;

   my $lv = [@{$self->{pl}->{data}->{look_vec}}];

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

   {
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
             [text => { color => "#888888" }, sprintf "%3d,%3d,%3d", @$pos],
             [text => { color => "#ffffff" }, int ($dist)],
             [text => { color => $alt_ok ? "#00ff00" : "#ff0000" }, $alt],
             [text => { color => $dir_ok ? "#00ff00" : "#ff0000" }, $r],
          ],
         ],
      ],
   }
}


sub layout_sector {
   my ($self, $pos) = @_;

   if ($pos) {
      $self->{nav_to_sector} = $pos;
   } else {
      ($pos) = $self->{nav_to_sector} || [0, 0, 0];
   }

   my $sec_pos  = $self->{pl}->get_pos_sector;
   my $dest_pos = [@$pos];

   my $diff = vsub ($dest_pos, $sec_pos);

   my $alt =
      $diff->[1] > 0
         ? $diff->[1] . " above"
         : ($diff->[1] < 0
             ? (-$diff->[1]) . " below" : "same height");
   my $alt_ok = $diff->[1] == 0;

   my $lv = [@{$self->{pl}->{data}->{look_vec}}];

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

   {
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
             [text => { color => "#888888" }, sprintf "%3d,%3d,%3d", @$pos],
             [text => { color => "#ffffff" }, int ($dist)],
             [text => { color => $alt_ok ? "#00ff00" : "#ff0000" }, $alt],
             [text => { color => $dir_ok ? "#00ff00" : "#ff0000" }, $r],
          ],
         ],
      ],
   }
}

package Games::Construder::Server::UI::SectorFinderSelect;
use Games::Construder::Vector;

use base qw/Games::Construder::Server::UI/;

sub commands {
   ( return => "select" )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'select') {
      $self->hide;
      my (@vec) = split /,/, $arg->{sector};
      pop @vec; # remove distance
      $self->show_ui ('navigator', sector => \@vec);
   }
}

sub layout {
   my ($self, $stype, $error) = @_;

   $self->{stype} = $stype;

   if ($error) {
      return {
         window => { pos => [center => 'center'], },
         layout => [
            box => { dir => "vert" },
            [text => { color => "#ff0000", align => "center" },
             "Sector with Type $stype not found anywhere near!"]
         ]
      };
   }

   my @sector_types =
      $Games::Construder::Server::RES->get_sector_types ();
   my ($s) = grep { $_->[0] eq $stype } @sector_types;

   my $sec_pos  = $self->{pl}->get_pos_sector;
   my $coord =
      Games::Construder::Region::get_nearest_sector_in_range (
         $Games::Construder::Server::World::REGION,
         @$sec_pos,
         $s->[1], $s->[2],
      );

   unless (@$coord) {
      $self->show ($stype, 1);
      return;
   }

   my @coords;
   while (@$coord) {
      my $p = [shift @$coord, shift @$coord, shift @$coord];
      push @coords, $p;
   }
   (@coords) = map { $_->[3] = vlength (vsub ($sec_pos, $_)); $_ } @coords;
   (@coords) = sort { $a->[3] <=> $b->[3] } @coords;
   splice @coords, 15;

   {
      window => {
         pos => [center => 'center'],
      },
      layout => [
         box => { dir => "vert" },
         [text => { color => "#ff0000", align => "center" },
          "Sector with Type $stype found at:\n"],
         (map {
            [select_box => {
               dir => "vert", align => "left", align => "center",
               arg => "sector", tag => join (",",@$_),
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
   }
}

package Games::Construder::Server::UI::SectorFinder;

use base qw/Games::Construder::Server::UI/;

sub init {
   my ($self) = @_;
   $self->new_ui (
      sector_finder_sec_select =>
         "Games::Construder::Server::UI::SectorFinderSelect");
}

sub commands {
   ( return => "select" )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'select') {
      my $st = $arg->{sector};
      $self->hide;
      $self->show_ui ('sector_finder_sec_select', $st);
   }
}

sub layout {
   my ($self) = @_;

   my @sector_types =
      $Games::Construder::Server::RES->get_sector_types ();

   my @grid;

   my $row = [];
   while (@sector_types) {
      push @$row, shift @sector_types;
      if (@$row > 3) {
         push @grid, $row;
         $row = [];
      }
   }
   push @grid, $row if @$row;

   {
      window => {
         pos => [center => 'center'],
      },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" }, padding => 10 },
         [text => { align => "center", font => "big", color => "#FFFFFF" },
          "Find sector..."],
         [text => { align => "center", font => "small", color => "#888888" },
          "Select a sector type with up/down keys and hit return."],
         [box => { align => "center", dir => "vert" },
         (map {
            my $row = $_;
            [box => { },
             map {
               [select_box => {
                  dir => "vert", align => "center", arg => "sector", tag => $_->[0],
                  padding => 2,
                  bgcolor => "#333333",
                  border => { color => "#555555", width => 2 },
                  select_border => { color => "#ffffff", width => 2 },
                  aspect => 1
                }, [text => { font => "normal", color => "#ffffff" }, $_->[0]]
               ]
             } @$row
            ]
         } @grid)],
      ]
   }
}

sub show_sector_finder {
   my ($self) = @_;


}


#R# sub ui_player_location_book {
#R#    my ($pl, $fetch, $set) = @_;
#R# 
#R#    $pl->displayed_uis (location_book => {
#R#       window => {
#R#       },
#R#       layout => [
#R#       ],
#R#       commands => {
#R#          default_keys => {
#R#             return => "set"
#R#          }
#R#       }
#R#    });
#R# }
sub show_location_book {
   my ($self) = @_;

   #R#ui_player_location_book ($pl, sub {
   #R#   map { [$_, $self->{data}->{tags}] } 0..9
   #R#}, sub {
   #R#   my ($slot, $name) = @_;
   #R#   $self->{data}->{tags}->[$slot] = $name, $chnk_pos, $sec_pos;
   #R#});
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

package Games::Construder::Server::UI::Assignment;

use base qw/Games::Construder::Server::UI/;

sub commands {
   (
      return => "generate",
      n => "navigate",
      c => "cancel_assign",
   )
}

sub handle_command {
   my ($self, $cmd) = @_;

   if ($cmd eq 'generate') {
      $self->{pl}->create_assignment;
      $self->show;

   } elsif ($cmd eq 'navigate') {
      $self->hide;
      $self->show_ui ('navigator', pos => $self->{pl}->{data}->{assignment}->{pos});

   } elsif ($cmd eq 'cancel_assign') {
      $self->{pl}->cancel_assignment;
   }
}

sub layout {
   my ($self) = @_;

   my $cal = $self->{pl}->{data}->{assignment} || {};
   my $mcal = { %$cal };
   delete $mcal->{pos_types};
   delete $mcal->{mat_models};

   {
      window => { pos => [ center => 'center' ] },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" } },
         [text => { color => "#ffffff" },
           JSON->new->pretty->encode ($mcal)],
      ]
   }
}

package Games::Construder::Server::UI::AssignmentTime;

use base qw/Games::Construder::Server::UI/;

sub commands {
   ( c => "rot_selection" )
}

sub handle_command {
   my ($self, $cmd) = @_;

   if ($cmd eq 'rot_selection') {
      $self->{pl}->assignment_select_next;
   }
}

sub layout {
   my ($self) = @_;

   my $cal = $self->{pl}->{data}->{assignment};

   my $color;
   if ($cal->{time} > 180) {
      $color = "#00ff00";
   } elsif ($cal->{time} > 90) {
      $color = "#00ffff";
   } else {
      $color = "#ff0000";
   }

   {
      window => { pos => [ left => "up", 0.1, 0 ], sticky => 1 },
      layout => [
         box => { dir => "vert" },
         [ text => { color => $color, align => "center" }, "Assignment:\n$cal->{time}s" ],
         [ text => { color => "#888888", align => "center" }, 
           "Left:\n" . join ("\n", map { "$_: $cal->{left}->{$_}" } keys %{$cal->{left}}) ],
         [ text => { color => "#ff8888", align => "center" }, 
           "Selected: " . $cal->{sel_mat} ],
      ]
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

