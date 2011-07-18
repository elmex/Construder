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

Games::Construder::Server::UI - Server-side Userinterface for Player interaction

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

sub hide_ui {
   my ($self, $name) = @_;
   $self->{pl}->{uis}->{$name}->hide;
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
use Games::Construder::UI;

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

   ui_hud_window ([center => "up"],
      [box => {
            border  => { color => $hl ? "#ff0000" : "#777700" },
            padding => ($hl ? 10 : 2),
            dir => "vert",
            },
         ($self->{pl}->{data}->{cheating}
            ? [text => { color => "#ff0000", font => "small", align => "center" },
               "<cheating>"]
            : ()),
         [box => {
               dir   => "hor",
               align => "center"
          },
          [text => {
             font  => "normal",
             color => "#aa8800",
             align => "center"
           }, "Score:"],
          [text => {
             font  => "big",
             color => $hl ? "#ff0000" : "#aa8800",
           }, ($score . ($hl ? ($hl > 0 ? "+$hl" : "$hl") : ""))],
         ],
      ]
   )
}

package Games::Construder::Server::UI::BioWarning;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub layout {
   my ($self, $seconds) = @_;

   ui_hud_window_transparent (
      [center => 'center', 0, -0.15],
      ui_warning (
          "Warning: Bio energy level low! You have $seconds seconds left!"
      ),
      ui_subdesc (
       "Death imminent, please dematerialize something that provides bio energy!",
      )
   )
}

package Games::Construder::Server::UI::ProximityWarning;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub commands {
}

sub handle_command {
   my ($self, $cmd) = @_;

}

sub layout {
   my ($self, $msg) = @_;

   my $wself = $self;
   weaken $wself;
   $self->{msg_tout} = AE::timer (3, 0, sub {
      $wself->hide;
      delete $wself->{msg_tout};
   });

   ui_hud_window_transparent (
      [center => "center", -0.25],
      ui_warning ($msg)
   );
}

package Games::Construder::Server::UI::MsgBox;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub layout {
   my ($self, $error, $msg) = @_;

   my $wself = $self;
   weaken $wself;
   $self->{msg_tout} = AE::timer (($error ? 7 : 3), 0, sub {
      $wself->hide;
      delete $wself->{msg_tout};
   });

   ui_hud_window_transparent (
      [center => "center", 0, 0.15],
      $error
         ? ui_warning ($msg)
         : ui_notice ($msg)
   )
}

package Games::Construder::Server::UI::Slots;
use Games::Construder::UI;

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

   if ($cmd =~ /slot_(\d+)/) {
      $self->{pl}->{data}->{slots}->{selected} = $1;
      $self->show;
   }
}

sub layout {
   my ($self) = @_;

   my $slots = $self->{pl}->{data}->{slots};

   my @slots;
   my $selected_type;
   for (my $i = 0; $i < 10; $i++) {
      my $invid = $slots->{selection}->[$i];

      my ($cnt) = $self->{pl}->{inv}->get_count ($invid);
      if ($invid =~ /:/ && $cnt == 0) {
         $slots->{selection}->[$i] = undef;
         $invid = undef;
      }

      my ($type, $invid) = $self->{pl}->{inv}->split_invid ($invid);
      if ($slots->{selected} == $i) {
         $selected_type = $type;
      }

      push @slots,
         ui_hlt_border (($i == $slots->{selected}),
            [box => { padding => 2, align => "center" },
              [model => { color => "#00ff00", width => 30 }, $type]],
            [text => { font => "small",
                       color =>
                          (!defined ($cnt) || $cnt <= 0) ? "#990000" : "#999999",
                       align => "center" },
             sprintf ("[%d] %d", $i + 1, $cnt * 1)]
         );
   }
   my @grid;
   $grid[0] = [splice @slots, 0, 5, ()];
   $grid[1] = \@slots;

   my $obj =
      $Games::Construder::Server::RES->get_object_by_type ($selected_type)
         if $selected_type;

   ui_hud_window ([left => "down"],
      $obj ? (ui_small_text ("Selected: " . $obj->{name})) : (),
      [box => { dir => "hor" }, @{$grid[0]}],
      [box => { dir => "hor" }, @{$grid[1]}]
   )
}

package Games::Construder::Server::UI::Help;
use Games::Construder::UI;
use base qw/Games::Construder::Server::UI/;

sub layout {
   ui_window ("Server Handled Keybindings",
      ui_desc ("Global Bindings:"),
      ui_key_explain ("left mouse btn",  "Materialize block from selected slot."),
      ui_key_explain ("right mouse btn", "Dematerialize block."),
      ui_key_explain ("q",               "Query information for highlighted block."),
      ui_key_explain ("e",               "Interact with highlighted block."),
      ui_key_explain ("i",               "Open inventory."),
      ui_key_explain ("n",               "Open navigator programmer."),
      ui_key_explain ("m",               "Toggle navigator visibility."),
      ui_key_explain ("x",               "Open assignment information."),
      ui_key_explain ("o",               "Open notebook."),
      ui_key_explain ("b",               "Open material handbook."),
      ui_key_explain ("r",               "Open color selector."),
      ui_key_explain ("l",               "Create encounter (developer stuff)."),
      ui_key_explain ("h",               "Cheat."),
      ui_key_explain ("F3",              "Displays this help screen."),
      ui_key_explain ("F4",              "Opens your trophy overview."),
      ui_key_explain ("F7",              "Display Server Information."),
      ui_key_explain ("F8",              "Commit suicide, when you want to start over."),
   )
}

package Games::Construder::Server::UI::ServerInfo;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub layout {
   ui_window ("Server Info",
      ui_text ("Server Map Directory: $Games::Construder::Server::Resources::MAPDIR"),
      ui_text ("Server Player Directory: $Games::Construder::Server::Resources::PLAYERDIR"),
   )
}

package Games::Construder::Server::UI::Status;
use Games::Construder::UI;
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
      f2  => "menu",
      f3  => "help",
      f4  => "trophies",
      f7  => "server_info",
      f8  => "kill",
      f11 => "text_script",
      f10 => "text_script_hide",
      f12 => "exit_server",
      i   => "inventory",
      n   => "navigation_programmer",
      m   => "toggle_navigator",
      h   => "cheat",
      x   => "assignment",
      t   => "location_book",
      e   => "interact",
      q   => "query",
      o   => "notebook",
      b   => "material_handbook",
      r   => "color_select",
      l   => "encounter"
   )
}

sub handle_command {
   my ($self, $cmd, $arg, $pos) = @_;

   my $pl = $self->{pl};

   if ($cmd eq 'inventory') {
      $self->show_ui ('inventory');
   } elsif ($cmd eq 'location_book') {
      $pl->show_location_book;
   } elsif ($cmd eq 'navigation_programmer') {
      $self->show_ui ('navigation_programmer');
   } elsif ($cmd eq 'cheat') {
      $self->show_ui ('cheat');
   } elsif ($cmd eq 'contact') {
      $self->show_ui ('ship_transmission');
   } elsif ($cmd eq 'interact') {
      $pl->interact ($pos->[0]) if @{$pos->[0] || []};
   } elsif ($cmd eq 'query') {
      $pl->query ($pos->[0]);
   } elsif ($cmd eq 'assignment') {
      $self->show_ui ('assignment');
   } elsif ($cmd eq 'material_handbook') {
      $self->show_ui ('material_handbook');
   } elsif ($cmd eq 'notebook') {
      $self->show_ui ('notebook');
   } elsif ($cmd eq 'color_select') {
      $self->show_ui ('color_select');
   } elsif ($cmd eq 'text_script') {
      $self->show_ui ('text_script');
   } elsif ($cmd eq 'text_script_hide') {
      $self->hide_ui ('text_script');
   } elsif ($cmd eq 'server_info') {
      $self->show_ui ('server_info');
   } elsif ($cmd eq 'encounter') {
      $self->{pl}->create_encounter;
   } elsif ($cmd eq 'kill') {
      $self->new_ui (kill_player =>
         "Games::Construder::Server::UI::ConfirmQuery",
         msg       => "Do you really want to commit suicide?",
         cb => sub {
            $self->delete_ui ('kill_player');
            $self->{pl}->kill_player ("suicide") if $_[0];
         });
      $self->hide;
      $self->show_ui ('kill_player');

   } elsif ($cmd eq 'help' || $cmd eq 'menu') {
      $self->show_ui ('help');
   } elsif ($cmd eq 'toggle_navigator') {
      if ($self->{pl}->{uis}->{navigator}->{shown}) {
         $self->hide_ui ('navigator');
      } else {
         $self->show_ui ('navigator');
      }
   } elsif ($cmd eq 'trophies') {
      $self->show_ui ("trophies");
   } elsif ($cmd eq 'exit_server') {
      $self->new_ui (shutdown =>
         "Games::Construder::Server::UI::ConfirmQuery",
         msg       => "Do you really want to shutdown the server?",
         cb => sub {
            $self->delete_ui ('shutdown');
            if ($_[0]) {
               $self->{pl}->msg (0, "Shutting down the server in 2 seconds...");
               my $t; $t = AE::timer 2, 0, sub {
                  $Games::Construder::Server::World::SRV->shutdown;
                  undef $t;
               };
            }
         });
      $self->hide;
      $self->show_ui ('shutdown');
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

sub time2str {
   my $m = int ($_[0] / 60);
   sprintf "%2dm %2ds", $m, $_[0] - ($m * 60)
}

sub layout {
   my ($self, $bio_usage) = @_;

   my $abs_pos  = $self->{pl}->get_pos_normalized;
   my $chnk_pos = $self->{pl}->get_pos_chnk;
   my $sec_pos  = $self->{pl}->get_pos_sector;

   my $sinfo = world_sector_info ($chnk_pos);

   if (ref $bio_usage) {
      my $wself = $self;
      weaken $wself;
      $self->{bio_intake} = $bio_usage;
      $self->{bio_intake_tmr} = AE::timer 2, 0, sub {
         delete $wself->{bio_intake};
         $wself->show;
         delete $wself->{bio_intake_tmr};
      };

   } elsif ($bio_usage) {
      my $wself = $self;
      weaken $wself;
      $self->{bio_usage} = $bio_usage;
      $self->{bio_usage_tmr} = AE::timer 2, 0, sub {
         delete $wself->{bio_usage};
         $wself->show;
         delete $wself->{bio_usage_tmr};
      };
   }

   ui_hud_window (
     [right => 'up'],
     ui_border (
        [box => { dir => "hor" },
           [box => { dir => "vert", padding => 2 },
              [text => { color => "#FFFF88", font => "small" }, "Time"],
              [text => { color => "#888888", font => "small" }, "Pos"],
              #d#[text => { color => "#888888", font => "small" }, "Look"],
              [text => { color => "#888888", font => "small" }, "Chunk"],
              [text => { color => "#888888", font => "small" }, "Sector"],
              [text => { color => "#888888", font => "small" }, "Type"],
           ],
           [box => { dir => "vert", padding => 2 },
              [text => { color => "#ffffff", font => "small" },
                 time2str ($self->{pl}->{data}->{time})],
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
           ($self->{bio_intake}
              ? [box => { dir => "hor", align => "left" },
                   [text => { align => "center", font => "big", color => "#00ff00", wrap => -2 }, "+"],
                   [model => { animated => 0, align => "center", width => 30 }, $self->{bio_intake}->[0]]]
              : [text => { align => "center", color => "#888888" }, "bio"])
        ],
        ($self->{bio_usage}
           ? [box => { },
              [text => { align => "center", color => "#FFaa00" }, "-$self->{bio_usage}% bio"]]
           : ()),
        [box => { },
           [text => { align => "right",
                      color => $self->{pl}->{data}->{signal_jammed}
                         ? "#00ff00" : "#ff0000" },
              $self->{pl}->{data}->{signal_jammed} ? "Jammed" : "Clear"],
           [text => { align => "center", color => "#888888" }, " signal"],
        ],
      )
   )
}

package Games::Construder::Server::UI::ListQuery;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub commands {
   ( return => "select" )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'select') {
      $self->{cb}->($self->{items}->[$arg->{item}]->[1]);

   } elsif ($cmd eq 'cancel') {
      $self->{cb}->();
   }
}

sub layout {
   my ($self) = @_;

   my $i = 0;
   ui_window ($self->{msg},
      ui_key_inline_expl ([qw/up down/], "Select item"),
      ui_key_inline_expl (return => "Confirm selection"),
      map { ui_select_item (item => $i++, ui_text ($_->[0])) } @{$self->{items}}
   )
}

package Games::Construder::Server::UI::ConfirmQuery;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub init {
}

sub commands {
   (
      y => "yes"
   )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'yes') {
      $self->{cb}->(1);

   } elsif ($cmd eq 'cancel') {
      $self->{cb}->(0);
   }
}

sub layout {
   my ($self) = @_;

   my $msg = $self->{msg};

   ui_window ("Confirmation Request",
      ui_desc ($msg),
      ui_key_explain ("y", "Yes"),
      ui_key_explain ("escape", "No"),
   );
}

package Games::Construder::Server::UI::StringQuery;
use Games::Construder::UI;

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

   if ($cmd eq 'enter') {
      $self->{cb}->($arg->{txt});

   } elsif ($cmd eq 'cancel') {
      $self->{cb}->();
   }
}

sub layout {
   my ($self) = @_;

   my $msg = $self->{msg};

   ui_window ($msg,
      ui_key_inline_expl (return => "Confirm entered text"),
      ui_entry (txt => $self->{txt}, 30),
   )
}

package Games::Construder::Server::UI::CountQuery;
use Games::Construder::UI;

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

   ui_window ($msg,
      ($error ?
         [text => { align => "center", color => "#ff0000" },
          "Entered value: $error, is too high!"] : ()),
      ui_pad_box (vert =>
         ui_entry (cnt => $self->{max_count}, length ($self->{max_count})),
         ui_subdesc ("Max: $self->{max_count}")),
   )
}

package Games::Construder::Server::UI::Paged;
use Games::Construder::UI;
use Games::Construder::Server::World;

use base qw/Games::Construder::Server::UI/;

sub init {
   my ($self) = @_;
   $self->{per_page} = 9;
}

sub commands {
   (
      'page down' => "pdown",
      'page up' => "pup",
   )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'pdown') {
      $self->{page}++;
      $self->show;

   } elsif ($cmd eq 'pup') {
      $self->{page}--;
      $self->show;
   }
}

sub elements {
   (0, [])
}

sub cur_page {
   my ($self) = @_;

   my ($cntelem, $ar) = $self->elements;
   my $pp      = $self->{per_page};
   my $page_cnt =
      (($cntelem % $pp != 0 ? 1 : 0) + int ($cntelem / $pp));

   $self->{page} = 0         if $self->{page} < 0;
   if ($page_cnt > 0) {
      $self->{page} = $page_cnt - 1 if $self->{page} >= $page_cnt;
   }
   my $page = $self->{page};

   ($page, $page_cnt, $pp, [splice @$ar, $page * $pp, $pp])
}

package Games::Construder::Server::UI::Trophies;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI::Paged/;

sub commands {
   my ($self) = @_;
   (
      $self->SUPER::commands (),
      return => "collect",
   )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'collect') {
      my $t = $arg->{trophy};
      $self->hide;
      $self->collect ($t);

   } else {
      $self->SUPER::handle_command ($cmd, $arg);
   }
}

sub collect {
   my ($self, $t) = @_;

   my $tr = $self->{pl}->{data}->{trophies}->{$t};
   my $ttype =
      $Games::Construder::Server::RES->get_trophy_type_by_score ($t);

   my $e = {
      label =>
         "Trophy for reaching the score $tr->[0] after "
         . time2str (int ($tr->[1])) . " playtime.",
   };

   if ($self->{pl}->{inv}->add ($ttype, $e)) {
      $tr->[2] = 1;
      $self->{pl}->msg (0, "Transferred the trophy for $tr->[0] score into your inventory!");
   } else {
      $self->{pl}->msg (1, "The trophy for $tr->[0] score does not fit into your inventory!");
   }
}

sub elements {
   my ($self) = @_;

   my $t = $self->{pl}->{data}->{trophies};

   my (@t) = map { $t->{$_} } sort {
      $b <=> $a
   } keys %$t;

   (scalar (@t), \@t)
}

sub time2str {
   my $m = int ($_[0] / 60);
   sprintf "%2dm %2ds", $m, $_[0] - ($m * 60)
}

sub layout {
   my ($self) = @_;

   my ($p, $lp, $epp, $elem) =
      $self->cur_page;

   ui_window ("Trophies",
      ui_desc (
       "Trophies " . (($p * $epp) + 1) . " to " . ((($p + 1) * $epp))),
      ui_key_inline_expl ("page up", "Previous page."),
      ui_key_inline_expl ("page down", "Next page."),
      map {
         $_->[2]
            ? ui_subtext (sprintf "%d after %s", $_->[0], time2str (int $_->[1]))
            : ui_select_item (trophy => $_->[0],
                 ui_text (sprintf "%d after %s", $_->[0], time2str (int $_->[1])))
      } @$elem
   )
}

package Games::Construder::Server::UI::MaterialView;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub commands {
   my ($self) = @_;

   my ($inv_cnt) = $self->{pl}->{inv}->get_count ($self->{invid});
   $inv_cnt or return ();

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
      last unless @k;
      $k = shift @k;
   }

   $PERC{$k}
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   my $invid = $self->{invid};

   if ($cmd =~ /slot_(\d+)/) {
      $self->{pl}->{data}->{slots}->{selection}->[$1] = $invid;
      $self->{pl}->{data}->{slots}->{selected} = $1;
      $self->show_ui ('slots');
      $self->hide;

   } elsif ($cmd eq 'discard') {
      $self->hide;
      my ($cnt) = $self->{pl}->{inv}->get_count ($invid);
      $self->new_ui (discard_material =>
         "Games::Construder::Server::UI::CountQuery",
         msg       => "Discard how many?",
         max_count => $cnt,
         cb => sub {
            if (defined $_[0]) {
               my ($cnt, $ent) = $self->{pl}->{inv}->remove ($invid, $_[0]);
               Games::Construder::Server::Objects::destroy ($ent) if $ent;
            }
            $self->delete_ui ('discard_material');
         });
      $self->show_ui ('discard_material');
   }
}

sub layout {
   my ($self, $type, $ent) = @_;

   $self->{invid} = $type;
   my ($type, $invid) = $self->{pl}->{inv}->split_invid ($type);
   my ($inv_cnt) = $self->{pl}->{inv}->get_count ($invid);

   unless ($ent) {
      $ent = $self->{pl}->{inv}->get_entity ($invid);
   }

   my $o =
      $Games::Construder::Server::RES->get_object_by_type ($type);
   my @sec =
      $Games::Construder::Server::RES->get_sector_types_where_type_is_found ($type);
   my @destmat =
      $Games::Construder::Server::RES->get_types_where_type_is_source_material ($type);
   my @srcmat =
      $Games::Construder::Server::RES->get_type_source_materials ($type);

   my @subtxts;
   push @subtxts,
      "Its complexity is " . _perc_to_word ($o->{complexity})
      . " and its density is " . _perc_to_word ($o->{density});
   push @subtxts,
      @sec
         ? "It can be found in sectors with following types: " . join (", ", @sec)
         : "It cannot be found in any sector.";
   push @subtxts,
      @destmat
         ? "It can be used as source material for: "
           . join (", ", map { $_->{name} } @destmat)
         : "It can't be processed any further.";
   push @subtxts,
      $inv_cnt
         ? "You have $inv_cnt of it in your inventory."
         : "You don't have any of it in your inventory.";

   ui_window ($o->{name},
      ui_pad_box (hor =>
         [box => { dir => "vert", align => "left" },
            ui_text ($o->{lore}, align => "left", wrap => 36),
            ($ent && $ent->{label} ne ''
               ? (ui_subtext ("This $o->{name} is labelled:"),
                 ui_text ("$ent->{label}"))
               : ()),
            (map { ui_subtext ($_, wrap => 36, align => "left") } @subtxts),
            [box => { dir => "vert", align => "center" },
               $inv_cnt ? (
                  ui_key_explain ("0-9", "Assign to slot."),
                  ui_key_explain (d => "Discard material."),
               ) : ()
            ],
            [text => { color => "#666666", font => "small" }, "(" . $o->{type} . ")"],
         ],
         ui_border (
            ui_pad_box (vert =>
               [model => { align => "center", animated => 0, width => 140 }, $o->{type}],
               (@srcmat && $o->{model_cnt} > 0
                  ? [box => { dir => "vert", align => "left" },
                     ui_small_text (
                        "Build Pattern:\n"
                        . join ("\n", map { $_->[1] . "x " . $_->[0]->{name} } @srcmat)
                       . "\nYields " . ($o->{model_cnt} || 1) . " $o->{name}"),
                    [model => { animated => 1, width => 120, align => "center" }, $o->{type}],
                  ] : ()),
            )
         ),
      ),
   )
}

package Games::Construder::Server::UI::QueryPatternStorage;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub build_grid {
   my ($self) = @_;

   my $inv = $self->{pat_store};

   my @grid;

   my @invids = $inv->get_invids;
   my @shortcuts = qw/
      1 q a y 2 w s x
      3 e d c 4 r f v
      5 t g b 6 z h n
      7 u j m 8 i k ,
   /;

   for (0..5) {
      my @row;
      for (0..3) {
         my $i = (shift @invids) || 1;
         my ($type, $i) = $inv->split_invid ($i);
         my $o = $Games::Construder::Server::RES->get_object_by_type ($type);
         my ($cnt) = $inv->get_count ($i);
                    # invid, inv count, object info, shortcut
         push @row, [$i, $cnt, $o, shift @shortcuts];
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
      map { $_->[3] => "short_" . $_->[0] }
         map { @$_ } @$grid
   )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'select') {
      $self->hide;
      $self->{cb}->($arg->{item}->[0]);

   } elsif ($cmd =~ /short_(\S+)/) {
      $self->hide;
      $self->{cb}->($1);

   } elsif ($cmd eq 'cancel') {
      $self->{cb}->();
   }
}

sub layout {
   my ($self) = @_;

   $self->build_grid;

   my $inv = $self->{pat_store};
   my ($free, $max) = $inv->free_density;
   my $cap = int (100 * (1 - ($free / $max)));

   my $cap_clr =
        $cap >= 90 ? "#ff0000"
      : $cap >= 70 ? "#ffff00"
      : "#00ff00";

   ui_window ($self->{title},
      [text => { font => "big", color => $cap_clr, align => "center" },
       "Used capacity: $cap%"],
      ui_key_inline_expl (
         "<shortcut key>",
         "Every material has it's own shortcut key to directly select it."),
      ui_key_inline_expl (
         [qw/up down/], "Select material by skipping through them"),
      ui_key_inline_expl (return => "Confirm selection."),
      [box => { dir => "hor" },
         (map {
            [box => { dir => "vert", padding => 4 },
               map {
                  [box => { padding => 1 },
                     ui_select_item (item => $_,
                        [box => { dir => "vert", padding => 4 },
                           [box => { dir => "hor", align => "left" },
                              [model => { align => "center", width => 60 }, $_->[0]],
                              ui_pad_box (vert => ui_text ($_->[1] ? $_->[1] : "0")),
                           ],
                           [box => { dir => "hor", align => "left" },
                              ui_key ($_->[3], font => "small"),
                              ui_small_text ($_->[0] == 1 ? "<empty>" : $_->[2]->{name})
                           ]
                        ]
                     )
                  ]
               } @$_
            ]
         } @{$self->{grid}})
      ],
   )
}

package Games::Construder::Server::UI::Inventory;

use base qw/Games::Construder::Server::UI::QueryPatternStorage/;

sub init {
   my ($self) = @_;
   $self->{title} = "Inventory";
   $self->{cb} = sub {
      my ($type) = @_;
      defined $type or return;
      $self->show_ui ('material_view', $type);
   };
}

sub layout {
   my ($self, @arg) = @_;
   $self->{pat_store} = $self->{pl}->{inv};
   $self->SUPER::layout (@arg);
}

package Games::Construder::Server::UI::Cheat;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub commands {
   my ($self) = @_;

   if ($self->{pl}->{data}->{cheating}) {
      (
        d => "killdrone",
        return => "cheat",
        p => "teleport",
      )
   } else {
      ( y => "enable" )
   }
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'cheat') {
      my $t = $arg->{type};
      my $spc = $self->{pl}->{inv}->space_for ($t);
      $self->{pl}->push_tick_change (score_punishment => $self->{pl}->{data}->{score});
      $self->{pl}->{inv}->add ($t, $spc);
      $self->hide;

   } elsif ($cmd eq 'enable') {
      $self->{pl}->{data}->{cheating} = 1;
      $self->{pl}->push_tick_change (score_punishment => $self->{pl}->{data}->{score});
      $self->show_ui ("score");
      $self->show;

   } elsif ($cmd eq 'killdrone') {
      $self->{pl}->push_tick_change (score_punishment => $self->{pl}->{data}->{score});
      $self->{pl}->{data}->{kill_drone} = 1;
      $self->hide;

   } elsif ($cmd eq 'teleport') {
      $self->{pl}->push_tick_change (score_punishment => $self->{pl}->{data}->{score});
      $self->{pl}->{uis}->{navigator}->teleport;
      $self->hide;
   }
}

sub layout {
   my ($self) = @_;

   unless ($self->{pl}->{data}->{cheating}) {
      return ui_window ("Enable Cheating?",
         ui_desc ("Do you want to enable cheating?"),
         ui_desc (
            "Enabling cheating will reset your score to 0 and "
            . "mark your score as being cheated."),
         ui_key_explain ("escape" => "Close dialog."),
         ui_key_explain ("y" => "Enable cheating."),
      )
   }
   ui_window ("Cheating",
      ui_text (
         "What material do you want to max out in your inventory? "
         . "Be careful, your score will be reset to 0!"),
      ui_pad_box (hor =>
         ui_desc ("Material Type:"),
         ui_entry (type => "", 4),
      ),
      ui_key_explain (return => "Maxes out entered material."),
      ui_key_explain (d => "Kills approaching drone."),
      ui_key_explain (p => "Teleports to destination of navigator."),
   )
}

package Games::Construder::Server::UI::Navigator;
use Games::Construder::UI;
use Games::Construder::Vector;
use Math::Trig qw/deg2rad rad2deg pi tan atan/;

use base qw/Games::Construder::Server::UI/;

sub commands {
}

sub handle_command {
   my ($self, $cmd) = @_;
   if ($cmd eq 'close') {
      $self->hide;
   }
}

sub teleport {
   my ($self) = @_;
   if ($self->{nav_to_pos}) {
      $self->{pl}->teleport ($self->{nav_to_pos});
   } else {
      $self->{pl}->teleport (vsmul ($self->{nav_to_sector}, 60));
   }
}

sub layout {
   my ($self, $type, $pos) = @_;

   if ($type eq 'pos') {
      $self->{nav_to_pos} = $pos;
      delete $self->{nav_to_sector};

   } elsif ($type eq 'sector') {
      $self->{nav_to_sector} = $pos;
      delete $self->{nav_to_pos};
   }

   my ($from, $to);
   if ($self->{nav_to_sector}) {
      $from = $self->{pl}->get_pos_sector;
      $to = $self->{nav_to_sector} || [0, 0, 0];
   } else {
      $from = $self->{pl}->get_pos_normalized;
      $to = $self->{nav_to_pos} || [0, 0, 0];
   }

   $self->layout_dir ($from, $to)
}

sub calc_direction_from_to {
   my ($self, $from, $to) = @_;

   my $diff = vsub ($to, $from);

   my $alt_dir =
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

   my $lr_dir;
   my $lr_ok;
   if ($l > 0.001) {
      vinorm ($lv);
      vinorm ($diff);
      my $pdot = $lv->[0] * $diff->[2] - $lv->[2] * $diff->[0];
      $lr_dir = rad2deg (atan2 ($pdot, vdot ($lv, $diff)), 1);
      $lr_dir = int $lr_dir;
      $lr_ok = abs ($lr_dir) < 10;
      $lr_dir = $lr_dir < 0 ? -$lr_dir . "° left" : $lr_dir . "° right";

   } else {
      $lr_dir = 0;

      if ($dl <= 0.001) { # we arrived!
         $lr_ok = 1;
      }
   }

   ($alt_dir, $alt_ok, $lr_dir, $lr_ok, $dist)
}

sub layout_dir {
   my ($self, $from, $to) = @_;
   my ($alt_dir, $alt_ok, $lr_dir, $lr_ok, $dist)
      = $self->calc_direction_from_to ($from, $to);

   ui_hud_window_transparent (
      ["right", "center"],
      ui_small_text ("Navigator"),
      [box => {
         dir => "hor",
       },
       [box => { dir => "vert", padding => 4 },
          ui_text ($self->{nav_to_pos} ? "Pos" : "Sec", align => "right"),
          ui_text ("Dest", align => "right"),
          ui_text ("Dist", align => "right"),
          ui_text ("Alt", align => "right"),
          ui_text ("Dir", align => "right"),
       ],
       [box => { dir => "vert", padding => 4 },
          ui_text ((sprintf "%3d,%3d,%3d", @$from), align => "left"),
          ui_text ((sprintf "%3d,%3d,%3d", @$to), align => "left"),
          ui_text (int ($dist), align => "left"),
          [text => { align => "left", color => $alt_ok ? "#00ff00" : "#ff0000" }, $alt_dir],
          [text => { align => "left", color => $lr_ok  ? "#00ff00" : "#ff0000" }, $lr_dir],
       ],
      ],
      ui_key_inline_expl (m => "Toggle Nav. Visibility"),
   )
}

package Games::Construder::Server::UI::SectorFinder;
use Games::Construder::UI;
use Games::Construder::Vector;

use base qw/Games::Construder::Server::UI/;

sub commands {
   ( return => "select" )
}

sub coords_for_sector_type {
   my ($self, $stype) = @_;

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
   @coords
}


sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'select') {
      my $st = $arg->{sector};

      my @coords = $self->coords_for_sector_type ($st);

      $self->new_ui (nav_prog_sector_select =>
         "Games::Construder::Server::UI::ListQuery",
         msg => "Closest Sectors with type $st",
         items =>
            [map { [ sprintf ("%d,%d,%d: %d", @$_) , $_] } @coords],
         cb  => sub {
            my ($coord) = @_;
            $self->delete_ui ('nav_prog_sector_select');
            if ($coord) {
               pop @$coord; # remove distance
               $self->show_ui ('navigator', sector => $coord);
            }
         });
      $self->hide;
      $self->show_ui ('nav_prog_sector_select');
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

   ui_window ("Find Sector by Type",
      ui_key_inline_expl ([qw/up down/], "Select sector type."),
      ui_key_inline_expl (return => "Confirm selection."),
      [box => { align => "center", dir => "vert" },
         (map {
            my $row = $_;
            [box => { dir => "hor" },
               map {
                  ui_select_item (sector => $_->[0], ui_text ($_->[0]))
               } @$row
            ]
         } @grid)
      ],
   )
}

package Games::Construder::Server::UI::NavigationProgrammer;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub commands {
   (
      p => "pos",
      s => "sec",
      t => "type",
      b => "beacon",
   )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'pos') {
      $self->new_ui (nav_prog_pos =>
         "Games::Construder::Server::UI::StringQuery",
         msg => "Please enter the absolute position to navigate to:",
         txt => (join ", ", @{$self->{pl}->get_pos_normalized}),
         cb  => sub {
            $self->delete_ui ('nav_prog_pos');
            $self->show_ui ('navigator', pos => [split /\s*,\s*/, $_[0]]);
         });
      $self->hide;
      $self->show_ui ('nav_prog_pos');

   } elsif ($cmd eq 'sec') {
      $self->new_ui (nav_prog_pos =>
         "Games::Construder::Server::UI::StringQuery",
         msg => "Please enter the absolute sector position to navigate to:",
         txt => (join ",", @{$self->{pl}->get_pos_sector}),
         cb  => sub {
            $self->delete_ui ('nav_prog_pos');
            $self->show_ui ('navigator', sector => [split /\s*,\s*/, $_[0]]);
         });
      $self->hide;
      $self->show_ui ('nav_prog_pos');

   } elsif ($cmd eq 'beacon') {
      $self->new_ui (nav_prog_beacon_select =>
         "Games::Construder::Server::UI::ListQuery",
         msg => "Please select the synchronized beacon you want to navigate to:",
         items => [
            map {
               my ($secs, $beacon) = @$_;
               [$beacon->[1] . " sync " . int ($secs / 60) . "m ago", $beacon->[0]]
            } sort { $a->[0] <=> $b->[0] } map {
               [int ($self->{pl}->now - $_->[2]), $_]
            } values %{$self->{pl}->{data}->{beacons}}
         ],
         cb  => sub {
            $self->delete_ui ('nav_prog_beacon_select');
            $self->show_ui ('navigator', pos => $_[0]);
         });
      $self->hide;
      $self->show_ui ('nav_prog_beacon_select');


   } elsif ($cmd eq 'type') {
      $self->hide;
      $self->show_ui ("sector_finder");
   }
}

sub layout {
   my ($self) = @_;

   ui_window ("Navigation Programmer",
      ui_desc ("Select a way to program the navigator."),
      ui_key_explain (p => "Navigate to position."),
      ui_key_explain (s => "Navigate to sector."),
      ui_key_explain (t => "Navigate to sector type."),
      ui_key_explain (b => "Navigate to recently synchronized message beacon."),
   )
}

package Games::Construder::Server::UI::Assignment;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub commands {
   my ($self) = @_;

   if ($self->{pl}->{data}->{assignment}) {
      return (
         n => "navigate",
         z => "cancel_assign",
      )
   } else {
      return (
         o => "reset_offers",
         1 => "offer_0",
         2 => "offer_1",
         3 => "offer_2",
         4 => "offer_3",
         5 => "offer_4",
      )
   }
}

sub handle_command {
   my ($self, $cmd) = @_;

   if ($cmd eq 'reset_offers') {
      $self->{pl}->{data}->{offers} = [];
      $self->show;

   } elsif ($cmd eq 'navigate') {
      $self->hide;
      $self->show_ui ('navigator', pos => $self->{pl}->{data}->{assignment}->{pos});

   } elsif ($cmd eq 'cancel_assign') {
      $self->{pl}->cancel_assignment;
      $self->hide;

   } elsif ($cmd =~ /offer_(\d+)/) {
      $self->{pl}->take_assignment ($1);
      $self->show;
   }
}

sub layout {
   my ($self) = @_;

   if ($self->{pl}->{data}->{assignment}) {
      return $self->layout_assignment;
   } else {
      return $self->layout_offers;
   }
}

my %DIFFMAP = (
   0 => "very easy",
   1 => "easy",
   2 => "mediocre",
   3 => "hard",
   4 => "very hard",
);

sub time2str {
   my $m = int ($_[0] / 60);
   sprintf "%2dm %2ds", $m, $_[0] - ($m * 60)
}

sub layout_offers {
   my ($self) = @_;

   my $off = $self->{pl}->{data}->{offers};

   ui_window ("Assignment Offers",
      map {
         [box => { align => "left" }, ui_pad_box (hor =>
            ui_key ($_->{diff} + 1),
            [box => { dir => "vert" },
               ui_desc ("Time / Expires:", align => "right"),
               ui_desc ("Score / Punishment:", align => "right"),
               ui_desc ("Materials:", align => "right"),
            ],
            [box => { dir => "vert" },
               ui_text (time2str ($_->{time}) . " / " . time2str ($_->{offer_time}),
                        align => "left"),
               ui_text ($_->{score} . " / " . -$_->{punishment}, align => "left"),
               ui_small_text (
                  (join ", ", map {
                     my $o =
                        $Games::Construder::Server::RES->get_object_by_type ($_->[2]);
                     $o->{name}
                  } @{$_->{material_map}}), wrap => 60, align => "left")
            ],
         )]
      } @$off
   )
}

sub layout_assignment {
   my ($self) = @_;

   my $cal = $self->{pl}->{data}->{assignment} || {};

   ui_window ("Assignment",
      ui_desc ("You are currently on assignment."),
      [box => { dir => "hor" },
       [box => { dir => "vert" },
        ui_desc ("Type:", align => "left"),
        ui_desc ("Time left:", align => "left"),
        ui_desc ("Score:", align => "left"),
        ui_desc ("Punishment on\nfailure/cancellation:", align => "left"),
       ],
       [box => { dir => "vert" },
        ui_text ($cal->{type} || "Construction", align => "left"),
        ui_text (time2str ($cal->{time}), align => "left"),
        ui_text ($cal->{score}, align => "left"),
        ui_text ($cal->{punishment}, align => "left"),
       ],
      ],
      ui_key_explain (n => "Navigate to assignment."),
      ui_key_explain (z => "Cancel assignment (you will lose score!)"),
   )
}

package Games::Construder::Server::UI::AssignmentTime;
use Games::Construder::UI;

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

   my $time = $cal->{time};
   my $minutes = int ($time / 60);
   $time -= $minutes * 60;

   my $sel_mat =
      $Games::Construder::Server::RES->get_object_by_type ($cal->{sel_mat});
   my $left_txt = join ("\n", map {
      my $o = $Games::Construder::Server::RES->get_object_by_type ($_);
      sprintf "%-15s: %3d", $o->{name}, $cal->{left}->{$_}
   } keys %{$cal->{left}});

   ui_hud_window ([ left => "up", 0, 0.03 ],
      ui_border (
         ui_desc ("Assignment"),
         ui_subdesc ("Time Left: " . sprintf ("%2dm %2ds", $minutes, $time)),
         ui_desc ("Highlighted: " . $sel_mat->{name} ),
         ui_key_inline_expl ("c", "Cycle highlights"),
         ui_small_text ("Materials to Place:\n$left_txt"),
      )
   )
}

package Games::Construder::Server::UI::MessageBeaconList;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub commands {
}

sub handle_command {
}

sub layout {
   my ($self, $beacons) = @_;

   my (@top) = sort {
      $a->[2] <=> $b->[2]
   } values %$beacons;
   splice @top, 3;

   ui_hud_window_transparent (
      [ right => "down" ],
      @top
         ? ui_border (
              ui_desc ("Message Beacons:"),
              map { ui_subdesc ($_->[1]) } @top
           )
         : ()
   )
}

package Games::Construder::Server::UI::MessageBeacon;
use Games::Construder::UI;
use Games::Construder::Server::World;

use base qw/Games::Construder::Server::UI/;

sub commands {
   (
      e => "edit",
   )
}

sub handle_command {
   my ($self, $cmd) = @_;

   if ($cmd eq 'edit') {
      my ($pos, $ent) = @{$self->{entity}};
      $self->new_ui (edit_message_beacon =>
         "Games::Construder::Server::UI::StringQuery",
         msg => "Please enter the message for this beacon:",
         txt => $ent->{msg},
         cb  => sub {
            my $txt = $_[0];
            if (defined $txt) {
               world_mutate_entity_at ($pos, sub {
                  my ($pos, $cell) = @_;
                  return 0 unless $cell->[0] == 34;
                  my $ent = $cell->[-1];
                  $ent->{msg} = $txt;
                  $self->show;
                  1
               });
            }
            $self->delete_ui ('edit_message_beacon');
         });
      $self->hide;
      $self->show_ui ('edit_message_beacon');
   }
}

sub layout {
   my ($self, $pos, $entity) = @_;
   $self->{entity} = [$pos, $entity] if $pos;
   ($pos, $entity) = @{$self->{entity}};

   ui_window ("Message Beacon",
      ui_desc ($entity->{msg}),
      ui_key_inline_expl (e => "Edit message."),
   )
}

package Games::Construder::Server::UI::PatternStorage;
use Games::Construder::UI;
use Games::Construder::Server::World;
use Games::Construder::Server::Player;
use Games::Construder::Logging;

use base qw/Games::Construder::Server::UI/;

sub commands {
   (
      l => "label",
      i => "from_inv",
      p => "from_stor",
   )
}

sub handle_command {
   my ($self, $cmd) = @_;

   my ($pos, $ent) = @{$self->{pat_stor}};
   my $ps_hdl =
      Games::Construder::Server::PatStorHandle->new (
         data => $ent, slot_cnt => 24);#$Games::Construder::Server::Player::PL_MAX_INV);

   $ps_hdl->reg_cb (changed => sub {
      # force update:
      world_mutate_entity_at ($pos, sub {
         my ($pos, $cell) = @_;
         return 0 unless $cell->[0] == 31;
         1
      });
   });

   if ($cmd eq 'label') {
      my ($pos, $ent) = @{$self->{pat_stor}};
      $self->new_ui (label_pattern_store =>
         "Games::Construder::Server::UI::StringQuery",
         msg => "Please enter the label for this pattern storage:",
         txt => $ent->{label},
         cb  => sub {
            my $txt = $_[0];
            if (defined $txt) {
               world_mutate_entity_at ($pos, sub {
                  my ($pos, $cell) = @_;
                  return 0 unless $cell->[0] == 31;
                  my $ent = $cell->[-1];
                  $ent->{label} = $txt;
                  $self->show;
                  1
               });
            }
            $self->delete_ui ('label_pattern_store');
         });
      $self->hide;
      $self->show_ui ('label_pattern_store');

   } elsif ($cmd eq 'from_inv') {
      $self->new_ui (pat_store_inv_selector =>
         "Games::Construder::Server::UI::QueryPatternStorage",
         title => "Transfer from Inventory",
         pat_store => $self->{pl}->{inv},
         cb  => sub {
            my $invid = $_[0];
            if (defined $invid) {
               my $o = $Games::Construder::Server::RES->get_object_by_type ($invid);
               my ($num) = $self->{pl}->{inv}->get_count ($invid);
               my ($cnt, $ent) = $self->{pl}->{inv}->remove ($invid, $num);
               if ($cnt) {
                  my $cnt_added = $ps_hdl->add ($invid, $ent ? $ent : $num);
                  ctr_log (debug => "pattern_storage: transfer %s from inv %d added, %d num", $invid, $cnt_added, $num);
                  my $put_back = $num - $cnt_added;
                  if ($cnt_added) {
                     $self->{pl}->msg (
                        0, "Transfered $cnt_added $o->{name} into the pattern storage.");
                  } else {
                     $self->{pl}->msg (
                        1, "$num $o->{name} does not fit into the pattern storage.");
                  }

                  $self->{pl}->{inv}->add ($invid, $ent ? $ent : $put_back) if $put_back;
               }
            }
            $self->delete_ui ('label_pattern_store');
         });
      $self->hide;
      $self->show_ui ('pat_store_inv_selector');

   } elsif ($cmd eq 'from_stor') {
      $self->new_ui (pat_store_inv_selector =>
         "Games::Construder::Server::UI::QueryPatternStorage",
         title => "Transfer from Pattern Storage",
         pat_store => $ps_hdl,
         cb  => sub {
            my $invid = $_[0];
            if (defined $invid) {
               my $o = $Games::Construder::Server::RES->get_object_by_type ($invid);
               my ($num) = $ps_hdl->get_count ($invid);
               my ($cnt, $ent) = $ps_hdl->remove ($invid, $num);
               if ($cnt) {
                  my $cnt_added = $self->{pl}->{inv}->add ($invid, $ent ? $ent : $num);
                  ctr_log (debug => "pattern_storage: transfer %s to inv %d added, %d num", $invid, $cnt_added, $num);
                  my $put_back = $num - $cnt_added;
                  if ($cnt_added) {
                     $self->{pl}->msg (
                        0, "Transfered $cnt_added $o->{name} into your inventory.");
                  } else {
                     $self->{pl}->msg (
                        1, "$num $o->{name} does not fit into your inventory.");
                  }

                  $ps_hdl->add ($invid, $ent ? $ent : $put_back) if $put_back;
               }
            }
            $self->delete_ui ('label_pattern_store');
         });
      $self->hide;
      $self->show_ui ('pat_store_inv_selector');
   }
}

sub layout {
   my ($self, $pos, $entity) = @_;
   $self->{pat_stor} = [$pos, $entity] if $pos;
   ($pos, $entity) = @{$self->{pat_stor}};

   ui_window ("Paggern Storage",
      ui_desc ($entity->{label}),
      ui_key_explain (l => "Label this storage."),
      ui_key_explain (i => "Transfer from inventory."),
      ui_key_explain (p => "Transfer from storage."),
   )
}

package Games::Construder::Server::UI::Notebook;
use Games::Construder::UI;
use Games::Construder::Server::World;

use base qw/Games::Construder::Server::UI/;

sub commands {
   (
      f6 => "prev",
      f7 => "next",
   )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   my $pg = $self->{pl}->{data}->{notebook}->{cur_page};

   if ($cmd eq 'save_text') {
      $self->{pl}->{data}->{notebook}->{main}->[$pg] = $arg->{page};

   } elsif ($cmd eq 'next') {
      $self->{pl}->{data}->{notebook}->{cur_page}++;
      $self->show;

   } elsif ($cmd eq 'prev') {
      $self->{pl}->{data}->{notebook}->{cur_page}--;
      if ($self->{pl}->{data}->{notebook}->{cur_page} < 0) {
         $self->{pl}->{data}->{notebook}->{cur_page} = 0;
      }
      $self->show;
   }
}

sub layout {
   my ($self) = @_;
   my $pg  = $self->{pl}->{data}->{notebook}->{cur_page};
   my $txt = $self->{pl}->{data}->{notebook}->{main}->[$pg];

   ui_window ("Notebook",
      ui_desc ("Page " . ($pg + 1)),
      ui_multiline (page => $txt),
      ui_key_inline_expl (F6 => "Previous page."),
      ui_key_inline_expl (F7 => "Next page."),
   )
}

package Games::Construder::Server::UI::MaterialHandbook;
use Games::Construder::UI;
use Games::Construder::Server::World;

use base qw/Games::Construder::Server::UI::Paged/;

sub init {
   my ($self) = @_;
   $self->{per_page} = 9;
}

sub elements {
   my ($self) = @_;

   my (@objs) =
      $Games::Construder::Server::RES->get_handbook_types;
   (@objs) = sort { $a->{name} cmp $b->{name} } @objs;

   (scalar (@objs), \@objs)
}

sub commands {
   my ($self) = @_;

   (
      $self->SUPER::commands (),
      return => "select",
   )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'select') {
      $self->hide;
      $self->show_ui ('material_view', $arg->{type});

   } else {
      $self->SUPER::handle_command ($cmd, $arg);
   }
}

sub layout {
   my ($self, $page) = @_;

   my ($page, $lastpage, $epp, $elements) =
      $self->cur_page;

   ui_window ("Material Handbook",
      ui_desc (
       "Materials " . (($page * $epp) + 1) . " to " . ((($page + 1) * $epp))),
      ui_key_inline_expl ("page up", "Previous page."),
      ui_key_inline_expl ("page down", "Next page."),
      (map {
         ui_select_item (type => $_->{type},
            ui_pad_box (hor =>
               [model => { width => 40, align => "left" }, $_->{type}],
               ui_text ($_->{name}, align => "center"),
            )
         )
      } @$elements),
   )
}

package Games::Construder::Server::UI::Teleporter;
use Games::Construder::UI;
use Games::Construder::Server::World;

use base qw/Games::Construder::Server::UI/;

sub commands {
   (
      return => "teleport",
      r      => "redirect",
   )
}

sub handle_command {
   my ($self, $cmd) = @_;

   if ($cmd eq 'teleport') {
      my $ent = world_entity_at ($self->{tele_pos});
      $self->hide;
      $self->{pl}->teleport ($ent->{pos});

   } elsif ($cmd eq 'redirect') {
      $self->new_ui (tele_redirect =>
         "Games::Construder::Server::UI::ListQuery",
         msg => "Please select the synchronized beacon you want to redirect the teleporter to:",
         items => [
            map {
               my ($secs, $beacon) = @$_;
               [$beacon->[1] . " sync " . int ($secs / 60) . "m ago",
                [$beacon->[0], $beacon->[1]]]
            } sort { $a->[0] <=> $b->[0] } map {
               [int ($self->{pl}->now - $_->[2]), $_]
            } values %{$self->{pl}->{data}->{beacons}}
         ],
         cb  => sub {
            $self->delete_ui ('tele_redirect');
            my ($tpos, $msg) = @{$_[0]};
            world_mutate_entity_at ($self->{tele_pos}, sub {
               my ($pos, $cell) = @_;
               return 0 unless $cell->[0] == 62;
               my $ent = $cell->[-1];
               $ent->{msg} = $msg;
               $ent->{pos} = [@$tpos];
               $self->show;
               1
            });
         });
      $self->hide;
      $self->show_ui ('tele_redirect');
   }
}

sub layout {
   my ($self, $pos) = @_;
   $self->{tele_pos} = [@$pos] if $pos;
   $pos = $self->{tele_pos};
   my $ent = world_entity_at ($pos);

   ui_window ("Teleporter",
      ($ent->{msg} ne '' ? ui_desc ("Destination: $ent->{msg}") : ()),
      ui_key_explain (return => "Teleport to destination."),
      ui_key_explain (r      => "Redirect teleporter to message beacon."),
   )
}


package Games::Construder::Server::UI::ColorSelector;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub commands {
   (
      return => "select"
   )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'select') {
      $self->{pl}->{colorifyer} = $arg->{color};
      $self->hide;
   }
}

my @CLRMAP = (
   [ 1,   1,   1   ],
   [ 0.6, 0.6, 0.6 ],
   [ 0.3, 0.3, 0.3 ],

   [ 0,   0,   1   ],
   [ 0,   1,   0   ],
   [ 1,   0,   0   ],

   [ 0.3, 0.3, 1   ],
   [ 0.3, 1,   0.3 ],
   [ 0.3, 1,   1   ],
   [ 1,   0.3, 1   ],
   [ 1,   1,   0.3 ],

   [ 0.6, 0.6, 1   ],
   [ 0.6, 1,   0.6 ],
   [ 0.6, 1,   1   ],
   [ 1,   0.6, 1   ],
   [ 1,   1,   0.6 ],

);

sub layout {
   my $nr = 0;
   ui_window ("Select Color",
      map {
         $nr++;
         my $clr = "#" . join '', map {
            sprintf "%02x", $_ * 255
         } @$_;
         ui_select_item (color => ($nr - 1), [text => { color => $clr }, sprintf ("#%02d#", $nr - 1)])
      } @CLRMAP
   )
}

package Games::Construder::Server::UI::ShipTransmission;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

my @keys = qw/1 2 3 4 5 6 7 8 9 a b c d e/;

sub commands {
   my $i = 0;
   (
      map { $_ => "resp_" . ($i++) } @keys
   )
}

sub handle_command {
   my ($self, $cmd) = @_;

   if ($cmd =~ /resp_(\d+)/) {
      $self->{node} = $self->{resp}->[$1]->[2];
      $self->update;
   }
}

sub layout {
   my ($self) = @_;

   my $inode = $self->{node}
               || $Games::Construder::Server::RES->get_ship_tree_at ("gen_i");
   $self->{node} = $inode;
   my $i = 0;
   my ($title, $text, @responses) = (
      $inode->{title},
      $inode->{text},
      map { [$i++, @$_] } @{$inode->{childs}}
   );

   $self->{resp} = \@responses;

   ui_window ("Ship Transmission: $title",
      ui_text ($text),
      map {
         ui_key_explain ($keys[$_->[0]], $_->[1])
      } @responses
   )
}

package Games::Construder::Server::UI::TextScript;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub layout {
   my ($self, $chrs) = @_;

   unless ($chrs) {
      my (@records) =
         split /\n/,
            join "\n", @{$self->{pl}->{data}->{notebook}->{main}};

      $self->{idx}++;
      if ($self->{idx} >= @records) {
         $self->{idx} = 0;
      }

      my $txt = $records[$self->{idx}];
      $txt =~ s/\\n/\n/g;
      $self->{cur_text} = $txt;
   }

   my $txt = $self->{cur_text};

   my $font = "normal";
   my $wrap = 40;
   if ($txt =~ s/^!big\s*//) {
      $font = "big";
      $wrap = 27;
   } elsif ($txt =~ s/^!small\s*//) {
      $font = "small";
      $wrap = 50;
   }
   my $pos = [ left => "center" ];
   if ($txt =~ s/^!middle\s*//) {
      $pos = [ center => "center" ];
   }

   my $tl = length $txt;

   $txt = substr $txt, 0, $chrs;

   my $w = ui_hud_window_above (
      $pos,
      [ text => { color => "#FFFF00", font => $font, wrap => $wrap }, $txt ]
   );

   my $add = 0.05;
   if ($txt =~ /[,\.]\s+$/s) {
      $add = 0.5; # even longer after dot or comma
   }

   $self->{timer} = AE::timer $add + rand (0.11), 0, sub {
      $self->show ($chrs + 1);
   };

   if ($tl <= $chrs) {
      delete $self->{timer};
   }

   $w
}

package Games::Construder::Server::UI::PCBProg;
use Games::Construder::Server::PCB;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub commands {
   (
      f4 => "stop",
      f5 => "start",
      f6 => "prev",
      f7 => "next",
      f8 => "reference",
   )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   my $pcb = Games::Construder::Server::PCB->new (p => $self->{ent}->{prog}, pl => $self->{pl});

   if ($cmd eq 'next') {
      $self->{page}++;
      $self->show;

   } elsif ($cmd eq 'prev') {
      $self->{page}--;
      if ($self->{page} < 0) {
         $self->{page} = 0;
      }
      $self->show;

   } elsif ($cmd eq 'stop') {
      $pcb->clear ();
      $self->{ent}->{time_active} = 0;

   } elsif ($cmd eq 'start') {
      $self->{ent}->{prog}->{txt} = join "\n", @{$self->{pl}->{data}->{prog}};
      my $err = $pcb->parse ();
      if ($err ne '') {
         $self->{pl}->msg (1, "Compiling prog failed: $err");

      } else {
         $pcb->clear ();
         $self->{ent}->{time_active} = 1;
      }

   } elsif ($cmd eq 'save_text') {
      $self->{pl}->{data}->{prog}->[$self->{page}] = $arg->{page};
      $self->show;

   } elsif ($cmd eq 'reference') {
      $self->{ref} = not $self->{ref};
      $self->show;

   }
}

sub layout {
   my ($self, $entity) = @_;

   $self->{ent} = $entity if $entity;

   my $prog = $self->{pl}->{data}->{prog}->[$self->{page}];
   $self->{ent}->{player} = $self->{pl}->{name};

   if ($self->{ref}) {
      return
      ui_window_special ("Programmer Reference", [ left => "center" ],

         ui_small_text (<<REF, wrap => 90),
<string> looks like: '"abc d e ef"', '"test"' or just bare 'test'.
<direction> is a string that can one of 6 values: forward, backward, left, right, up, down
<color> is a number from 0 to 15.
<callback> can be 'call:<labelname>' or 'jump:<labelname>'.
<material> is a string with the material name.

jump <string> <arguments> - Jumps to label <string>, setting variables arg0, arg1, ...
call <string> <arguments> - Saves return address and jumps to <string>, setting  variables as jump does.
return <arguments>        - Return from a call and set variables ret0, ret1, ...
stop                      - Halt the PCB.

mat <direction> <material> <color> <callback> - Materializes the material from inventory with color to direction.
vapo <direction> <callback> - Vaporizes the block in a certain direction. Calling/Jumping the callback with the material name that was vaporized.
move <direction> <callback> - Moves into the direction, calling/jumping the callback when the move failed with the name of the blocking material.
probe <direction> <callback> - Probes into a direction, calling/jumping the callback with the material name.
demat <direction> <callback> - Dematerializes material in a direction, calling the callback with an error as first and material name as second argument.
print <arguments> - Prints out the arguments as message to the player.
if <value_1> <cmp> <value_2> <callback> - Compares first with second value according to the comparator, calling/jumping the callback if comparions results in true. Available comparsions: ==, !=, <, >, <=, >=, eq, ne
var <variable name> <op> <value> [<output name>] - Executes an operation on the variable with the specified name. Possible operations: add, sub, mul, div, mod, set, append, prepend, pop, shift, unshift, push, at, turn

Notes:
The callback is always optional.

REF
         ui_key_inline_expl (F8 => "Hide Reference Sheet."),
      )
   } else {
      return
      ui_window_special ("Programmer", [ left => "center" ],
         ui_multiline (page => $prog, font => "small", height => 40, wrap => -42, max_chars => 42),
         ui_key_inline_expl (F4 => "Stop bot."),
         ui_key_inline_expl (F5 => "Start bot."),
         ui_key_inline_expl (F6 => "Previous page."),
         ui_key_inline_expl (F7 => "Next page."),
         ui_key_inline_expl (F8 => "Show Reference Sheet."),
      )
   }
}

package Games::Construder::Server::UI::Jumper;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub commands {
   (
      return => "activate"
   )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'activate') {
      $self->{entity}->{time_active} = 1;
      $self->{entity}->{disp_vec} =
         [$arg->{xdisp}, $arg->{ydisp}, $arg->{zdisp}];
      $self->hide;
   }
}

sub layout {
   my ($self, $type, $entity) = @_;

   $self->{entity} = $entity;

   my $obj =
      $Games::Construder::Server::RES->get_object_by_type ($type);

   my $r = $entity->{range};

   ui_window ($obj->{name},
      ui_desc ("Enter displacement direction:"),
      ui_subdesc ("Range: " . $entity->{range} . " sectors"),
      ui_subdesc ("Accuracy: " . (100 * $entity->{accuracy}) . "%"),
      ui_subdesc ("Malfunction: " . (100 * $entity->{fail_chance}) . "%"),
      ui_pad_box (hor =>
         ui_text ("X"),
         ui_range (xdisp => -$r, $r, $r > 40 ? 5 : 1, "%d", 0),
      ),
      ui_pad_box (hor =>
         ui_text ("Y"),
         ui_range (ydisp => -$r, $r, $r > 40 ? 5 : 1, "%d", 0),
      ),
      ui_pad_box (hor =>
         ui_text ("Z"),
         ui_range (zdisp => -$r, $r, $r > 40 ? 5 : 1, "%d", 0),
      ),
      ui_key_explain (return => "Activate jumper"),
   )
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

