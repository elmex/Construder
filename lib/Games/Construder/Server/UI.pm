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
        }, ($score . ($hl ? ($hl > 0 ? "+$hl" : "$hl") : ""))]
      ]
   )
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

package Games::Construder::Server::UI::ProximityWarning;
use Games::Construder::UI;

use base qw/Games::Construder::Server::UI/;

sub layout {
   my ($self, $msg) = @_;

   my $wself = $self;
   weaken $wself;
   $self->{msg_tout} = AE::timer (3, 0, sub {
      $wself->hide;
      delete $wself->{msg_tout};
   });

   ui_hud_window_transparent (
      [center => "center", 0.25],
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
      [center => "center", 0, 0.25],
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

   warn "CMD @_\n";

   if ($cmd =~ /slot_(\d+)/) {
      $self->{pl}->{data}->{slots}->{selected} = $1;
      $self->show;
   }
}

sub layout {
   my ($self) = @_;

   my $slots = $self->{pl}->{data}->{slots};

   my @slots;
   for (my $i = 0; $i < 10; $i++) {
      my $invid = $slots->{selection}->[$i];

      my ($cnt) = $self->{pl}->{inv}->get_count ($invid);
      if ($invid =~ /:/ && $cnt == 0) {
         $slots->{selection}->[$i] = undef;
         $invid = undef;
      }

      my ($type, $invid) = $self->{pl}->{inv}->split_invid ($invid);

      push @slots,
      ui_hlt_border (($i == $slots->{selected}),
         [box => { padding => 2, align => "center" },
           [model => { color => "#00ff00", width => 40 }, $type]],
         [text => { font => "small",
                    color =>
                       (!defined ($cnt) || $cnt <= 0) ? "#990000" : "#999999",
                    align => "center" },
          sprintf ("[%d] %d", $i + 1, $cnt * 1)]
      );
   }

   ui_hud_window ([left => "down"], [box => { dir => "hor" }, @slots]);
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
      ui_key_explain ("F3",              "Displays this help screen."),
      ui_key_explain ("F8",              "Commit suicide, when you want to start over."),
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
      f4  => "contact",
      f8  => "kill",
      f9  => "teleport_home",
      f11 => "text_script",
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
   } elsif ($cmd eq 'teleport_home') {
      $pl->teleport ([0, 0, 0]);
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
   } elsif ($cmd eq 'encounter') {
      $self->{pl}->create_encounter;
   } elsif ($cmd eq 'kill') {
      $self->new_ui (kill_player =>
         "Games::Construder::Server::UI::ConfirmQuery",
         msg       => "Do you really want to commit suicide?",
         cb => sub {
            $self->delete_ui ('discard_material');
            if ($_[0]) {
               $self->{pl}->kill_player ("suicide");
            }
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
   my ($self, $bio_usage) = @_;

   my $abs_pos  = $self->{pl}->get_pos_normalized;
   my $chnk_pos = $self->{pl}->get_pos_chnk;
   my $sec_pos  = $self->{pl}->get_pos_sector;

   my $sinfo = world_sector_info ($chnk_pos);

   if ($bio_usage) {
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
   {
      window => {
         pos => [center => 'center'],
      },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" }, padding => 10 },
         [text => { align => "center", font => "big", color => "#FFFFFF", wrap => 25 },
          $self->{msg}],
         [text => { align => "center", font => "small", color => "#888888" },
          "Select a list item with [up]/[down] keys and hit [return]."],
          map {
            [select_box => {
               dir => "vert", align => "center", arg => "item", tag => $i++,
               padding => 2,
               bgcolor => "#333333",
               border => { color => "#555555", width => 2 },
               select_border => { color => "#ffffff", width => 2 },
             }, [text => { font => "normal", color => "#ffffff" }, $_->[0]]
            ]
          } @{$self->{items}}
      ]
   }
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

   {
      window => {
         pos => [center => 'center'],
      },
      layout => [
         box => { dir => "vert" },
         [text => { color => "#ffffff", align => "center", wrap => 30 },
          $msg],
         [box => { dir => "hor", align => "center" },
            [text => { font => "normal", color => "#ffffff", align => "center" }, "Entry:"],
            [entry => { font => 'normal', color => "#ffffff", arg => "txt",
                        highlight => ["#111111", "#333333"], align => "center" },
             $self->{txt}]
         ]
      ]
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
   my ($self, $type) = @_;

   $self->{invid} = $type;
   my ($type, $invid) = $self->{pl}->{inv}->split_invid ($type);
   my ($inv_cnt) = $self->{pl}->{inv}->get_count ($invid);
   warn "MATVOIEW $inv_cnt |$type,$invid\n";

   my $o =
      $Games::Construder::Server::RES->get_object_by_type ($type);
   my @sec =
      $Games::Construder::Server::RES->get_sector_types_where_type_is_found ($type);
   my @destmat =
      $Games::Construder::Server::RES->get_types_where_type_is_source_material ($type);
   my @srcmat =
      $Games::Construder::Server::RES->get_type_source_materials ($type);

   {
      window => { pos => [center => 'center'] },
      layout => [
         box => { dir => "vert" },
          [box => { dir => "hor" },
           [text => { color => "#ffffff", font => "big"   }, $o->{name}],
           [text => { color => "#666666", font => "small" }, "(" . $o->{type} . ")"],
          ],
          [box => { dir => "hor", align => "left" },
             [text => { align => "left", color => "#ffffff", font => "normal", wrap => 35 }, $o->{lore}],
             [model => { align => "left", animated => 0, width => 80 }, $o->{type}],
             (@srcmat && $o->{model_cnt} > 0
               ? [box => { dir => "vert", align => "left" },
                  [text => { color => "#999999", font => "small", align => "center" },
                   "Build Pattern:\n"
                   . join ("\n", map { $_->[1] . "x " . $_->[0]->{name} } @srcmat)
                   . "\nYields " . ($o->{model_cnt} || 1) . " $o->{name}"],
                  [model => { animated => 1, width => 120, align => "center" }, $o->{type}],
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

package Games::Construder::Server::UI::QueryPatternStorage;

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

   {
      window => {
         pos => [center => 'center'],
      },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" } },
         [text => { font => "big", color => "#FFFFFF", align => "center" }, $self->{title}],
         [text => { font => "big", color => $cap_clr, align => "center" },
          "Used capacity: $cap%"],
         [text => { font => "small", color => "#888888", wrap => 40, align => "center" },
          "(Select a resource directly by [shortcut key] or [up]/[down] and hit [return].)"],
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
                         $_->[1] ? $_->[1] : "0"],
                        [model => { align => "center", width => 60 }, $_->[0]],
                        [text  => { font => "small", align => "center",
                                    color => "#ffffff", wrap => 10 },
                         $_->[0] == 1 ? "<empty>" : "[$_->[3]] $_->[2]->{name}"]
                     ]

                  } @$_
               ]
            } @{$self->{grid}})
         ]
      ],
   }
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

use base qw/Games::Construder::Server::UI/;

sub commands {
   ( return => "cheat" )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'cheat') {
      my $t = $arg->{type};
      my $spc = $self->{pl}->{inv}->space_for ($t);
      $self->{pl}->{data}->{score} = 0;
      $self->{pl}->update_score;
      warn "CHEAT: $t : $spc\n";
      $self->{pl}->{inv}->add ($t, $spc);
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
   (
      p => "teleport",
   )
}

sub handle_command {
   my ($self, $cmd) = @_;
   if ($cmd eq 'close') {
      $self->hide;
   } elsif ($cmd eq 'teleport') {
      if ($self->{nav_to_pos}) {
         $self->{pl}->teleport ($self->{nav_to_pos});
      } else {
         $self->{pl}->teleport (vsmul ($self->{nav_to_sector}, 60));
      }
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
             [text => { color => "#888888" }, $self->{nav_to_pos} ? "Pos" : "Sec"],
             [text => { color => "#888888" }, "Dest"],
             [text => { color => "#888888" }, "Dist"],
             [text => { color => "#888888" }, "Alt"],
             [text => { color => "#888888" }, "Dir"],
          ],
          [box => { dir => "vert", padding => 4 },
             [text => { color => "#888888" }, sprintf "%3d,%3d,%3d", @$from],
             [text => { color => "#888888" }, sprintf "%3d,%3d,%3d", @$to],
             [text => { color => "#ffffff" }, int ($dist)],
             [text => { color => $alt_ok ? "#00ff00" : "#ff0000" }, $alt_dir],
             [text => { color => $lr_ok  ? "#00ff00" : "#ff0000" }, $lr_dir],
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
          "Select a sector type with [up]/[down] keys and hit [return]."],
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

package Games::Construder::Server::UI::NavigationProgrammer;

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

   {
      window => {
         pos => [center => 'center'],
      },
      layout => [
         box => { dir => "vert" },
         [text => { font => "big", color => "#ffffff" },
          "Navigation Programmer"],
         [text => { align => "center", font => "small", color => "#888888" },
          "Select a way to program the navigator by hitting the [key]."],
         [text => { font => "normal", color => "#ffffff" },
          "[p] Navigate to position."],
         [text => { font => "normal", color => "#ffffff" },
          "[s] Navigate to sector."],
         [text => { font => "normal", color => "#ffffff" },
          "[t] Navigate to nearest sector type."],
         [text => { font => "normal", color => "#ffffff" },
          "[b] Navigate to recently synchronized message beacon."],
      ]
   }
}

package Games::Construder::Server::UI::Assignment;

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
      $self->show;

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

   {
      window => { pos => [ center => 'center' ] },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" } },
         [text => { color => "#ffffff", font => "big" }, "Assignment Offers"],
         [box => { dir => "hor" },
          [box => { dir => "vert", padding => 4 },
           [text => { color => "#888888" }, "Key"],
           map {
            [text => { color => "#ffffff" },
               "[" . ($_->{diff} + 1) . "]"]
           } @$off
          ],
          [box => { dir => "vert", padding => 4 },
           [text => { color => "#888888" }, "Type"],
           map {
            [text => { color => "#ffffff" },
               "Constr."]
           } @$off
          ],
          [box => { dir => "vert", padding => 4 },
           [text => { color => "#888888" }, "Time"],
           map {
            [text => { color => "#ffffff" },
               time2str ($_->{time})]
           } @$off
          ],
          [box => { dir => "vert", padding => 4 },
           [text => { color => "#888888" }, "Materials"],
           map {
            [text => { color => "#ffffff", wrap => 10 },
               join ",\n",
               map {
                  my $o =
                     $Games::Construder::Server::RES->get_object_by_type ($_->[2]);
                  $o->{name}
               } @{$_->{material_map}}]
           } @$off
          ],
          [box => { dir => "vert", padding => 4 },
           [text => { color => "#888888" }, "Score"],
           map {
            [text => { color => "#ffffff" },
               $_->{score}]
           } @$off
          ],
          [box => { dir => "vert", padding => 4 },
           [text => { color => "#888888" }, "Expiration"],
           map {
            [text => { color => "#ffffff" },
               time2str ($_->{offer_time})]
           } @$off
          ],
          [box => { dir => "vert", padding => 4 },
           [text => { color => "#888888" }, "Punishment"],
           map {
            [text => { color => "#ffffff" }, -$_->{punishment}]
           } @$off
          ],
         ],
      ]
   }

}

sub layout_assignment {
   my ($self) = @_;

   my $cal = $self->{pl}->{data}->{assignment} || {};

   {
      window => { pos => [ center => 'center' ] },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" } },
         [text => { color => "#ffffff", font => "big" }, "Assignment"],
         [text => { color => "#888888", font => "small" },
          "(You are currently on assignment)"],
         [box => { dir => "hor" },
          [box => { dir => "vert" },
           [text => { color => "#888888" }, "Type:"],
           [text => { color => "#888888" }, "Time left:"],
           [text => { color => "#888888" }, "Score:"],
           [text => { color => "#888888" }, "Difficulty:"],
           [text => { color => "#888888" }, "Punishment on\nfailure/cancellation:"],
          ],
          [box => { dir => "vert" },
           [text => { color => "#ffffff" }, $cal->{type} || "Construction"],
           [text => { color => "#ffffff" }, $cal->{time}],
           [text => { color => "#ffffff" }, $cal->{score}],
           [text => { color => "#ffffff" }, $DIFFMAP{$cal->{diff}}],
           [text => { color => "#ffffff" }, $cal->{punishment}],
          ],
         ],
         [text => { color => "#ffffff" },
          "[n] Navigate to assignment"],
         [text => { color => "#ffffff" },
          "[c] Cycle highlighted material\n   (also works globally from the HUD)"],
         [text => { color => "#ffffff" },
          "[z] Cancel assignment (you will lose score!)"],
      ]
   }
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

   {
      window => { pos => [ left => "up", 0.1, 0 ], sticky => 1 },
      layout => [
         box => { dir => "vert" },
         [ text => { color => $color, align => "center" },
            "Assignment: " . sprintf ("%2dm %2ds", $minutes, $time) ],
         [ text => { color => "#888888", align => "center" },
           "Left:\n$left_txt" ],
         [ text => { color => "#ff8888", align => "center" },
           "Highlighted: " . $sel_mat->{name} ],
         ui_key_inline_expl ("c", "Cycle highlights"),
      ]
   }
}

package Games::Construder::Server::UI::MessageBeaconList;
use Games::Construder::Server::World;

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

   {
      window => { pos => [ left => "up", 0, 0.07 ], sticky => 1, alpha => 0.5 },
      layout => [
         box => { dir => "vert" },
         @top
            ? (
               [text => { color => "#888888", font => "small" }, "message beacons:"],
               map {
                  [text => { color => "#ffff00" }, $_->[1]]
               } @top
            ) : ()
      ]
   }
}

package Games::Construder::Server::UI::MessageBeacon;
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

   {
      window => { pos => [ center => 'center' ] },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" } },
         [text => { color => "#ffffff", font => "big" }, "Message Beacon:\n$entity->{msg}"],
         [text => { color => "#ffffff" }, "[e] edit message"],
      ]
   }
}

package Games::Construder::Server::UI::PatternStorage;
use Games::Construder::Server::World;
use Games::Construder::Server::Player;

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
                  warn "set label @$pos: $cell->[0], $ent | $ent->{label}\n";
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
                  warn "OK TRANSFE $invid : $ent  | $num\n";
                  if ($ps_hdl->add ($invid, $ent ? $ent : $num)) {
                     $self->{pl}->msg (
                        0, "Transfered $num $o->{name} into the pattern storage.");
                  } else {
                  warn "TRANSFER FAILED\n";
                     $self->{pl}->{inv}->add ($invid, $ent ? $ent : $num);
                     $self->{pl}->msg (
                        1, "$num $o->{name} does not fit into the pattern storage.");
                  }
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
                  if ($self->{pl}->{inv}->add ($invid, $ent ? $ent : $num)) {
                     $self->{pl}->msg (
                        0, "Transfered $num $o->{name} into your inventory.");
                  } else {
                     $ps_hdl->add ($invid, $ent ? $ent : $num);
                     $self->{pl}->msg (
                        1, "$num $o->{name} does not fit into your inventory.");
                  }
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
   warn "LAYOUt PSTOR $entity\n";
   $self->{pat_stor} = [$pos, $entity] if $pos;
   ($pos, $entity) = @{$self->{pat_stor}};

   {
      window => { pos => [ center => 'center' ] },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" } },
         [text => { color => "#ffffff", font => "big" }, "Pattern Storage: $entity->{label}"],
         [text => { color => "#ffffff" }, "[l] to label this storage"],
         [text => { color => "#ffffff" }, "[i] to transfer from inventory"],
         [text => { color => "#ffffff" }, "[p] to transfer from storage"],
      ]
   }
}

package Games::Construder::Server::UI::Notebook;
use Games::Construder::Server::World;

use base qw/Games::Construder::Server::UI/;

sub commands {
   ( f4 => "clear" )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'save_text') {
      $self->{pl}->{data}->{notebook}->{main} = $arg->{page};

   } elsif ($cmd eq 'clear') {
      $self->{pl}->{data}->{notebook}->{main} = "";
      $self->show;
   }
}

sub layout {
   my ($self) = @_;
   my $txt = $self->{pl}->{data}->{notebook}->{main};
   {
      window => { pos => [ center => 'center' ] },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" } },
         [text => { color => "#ffffff" }, "Notebook:"],
         [box => { dir => "hor", padding => 3 },
         [
            multiline => {
                  font => 'normal', color => "#ffffff", arg => "page",
                  highlight => ["#111111", "#333333", "#663333"],
                  max_chars => 32, wrap => -32,
                  height => 25,
            },
            $txt
         ]],
         [text => { color => "#888888", font => "small" },
          "[f4] clears all text"],
      ]
   }
}

package Games::Construder::Server::UI::MaterialHandbook;
use Games::Construder::Server::World;

use base qw/Games::Construder::Server::UI/;

sub commands {
   (
      down => "down",
      'page down' => "down",
      up => "up",
      'page up' => "up",
      return => "select",
   )
}

sub handle_command {
   my ($self, $cmd, $arg) = @_;

   if ($cmd eq 'select') {
      $self->hide;
      $self->show_ui ('material_view', $arg->{type});

   } elsif ($cmd eq 'down') {
      $self->{page}++;
      $self->show;

   } elsif ($cmd eq 'up') {
      $self->{page}--;
      $self->show;
   }
}

sub layout {
   my ($self, $page) = @_;

   my (@objs) =
      $Games::Construder::Server::RES->get_handbook_types;
   (@objs) = sort { $a->{name} cmp $b->{name} } @objs;

   my $lastpage = ((@objs % 10 != 0 ? 1 : 0) + int (@objs / 10));

   $self->{page} = $page     if defined $page;
   $self->{page} = 0         if $self->{page} < 0;
   $self->{page} = $lastpage if $self->{page} > $lastpage;
   $page = $self->{page};

   my (@thispage) = splice @objs, $page * 10, 10;

   {
      window => { pos => [ center => 'center' ] },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" } },
         [text => { font => "big", color => "#ffffff" }, "Material Handbook"],
         [text => { font => "normal", color => "#ffffff" },
          "Materials " . (($page * 10) + 1) . " to " . ((($page + 1) * 10) + 1)],
         [text => { font => "small", color => "#888888" },
          "[page up] previous page\n[page down] next page"],
         (map {
            [select_box => {
               dir => "hor", align => "center", arg => "type", tag => $_->{type},
               padding => 2, bgcolor => "#333333",
               border => { color => "#555555", width => 2 },
               select_border => { color => "#ffffff", width => 2 },
             },
             [model => { width => 40, align => "center" }, $_->{type}],
             [text => { font => "normal", align => "center", color => "#ffffff" }, $_->{name}],
            ]
         } @thispage),
      ]
   }
}

package Games::Construder::Server::UI::Teleporter;
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

   {
      window => { pos => [ center => 'center' ] },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" } },
         [text => { color => "#ffffff", font => "big" }, "Teleporter to $ent->{msg}"],
         [text => { color => "#ffffff" }, "[return] teleport"],
         [text => { color => "#ffffff" }, "[r] redirect teleporter"],
      ]
   }
}


package Games::Construder::Server::UI::ColorSelector;
use Games::Construder::Server::World;

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
      warn "SET COLOr $arg->{color}\n";
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
   {
      window => { pos => [ center => 'center' ] },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" } },
         [text => { color => "#ffffff", font => "big" }, "Select color"],
         map {
            $nr++;
            my $clr = "#" . join '', map {
               sprintf "%02x", $_ * 255
            } @$_;
            [select_box => {
               dir => "hor", align => "center", arg => "color", tag => ($nr - 1),
               padding => 2, bgcolor => "#333333",
               border => { color => "#555555", width => 2 },
               select_border => { color => "#ffffff", width => 2 },
             },
               [text => { color => $clr }, "##"]
            ]
         } @CLRMAP
      ]
   }
}

package Games::Construder::Server::UI::ShipTransmission;
use Games::Construder::Server::World;

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

   {
      window => { pos => [ center => 'center' ] },
      layout => [
         box => { dir => "vert", border => { color => "#ffffff" } },
         [text => { color => "#ffffff", font => "big" },
          "Ship Interaction: $title"],
         [text => { color => "#ffffff", font => "normal", wrap => 45, align => "center" }, $text],
         map {
            [text => { color => "#ffffff", font => "normal" },
             "[$keys[$_->[0]]] $_->[1]"],
         } @responses
      ]
   }

}

package Games::Construder::Server::UI::TextScript;

use base qw/Games::Construder::Server::UI/;

sub layout {
   my ($self) = @_;

   my (@records) = split /\n/, $self->{pl}->{data}->{notebook}->{main};

   $self->{idx}++;
   if ($self->{idx} >= @records) {
      $self->{idx} = 0;
   }

   my $txt = $records[$self->{idx}];
   $txt =~ s/\\n/\n/g;

   {
      window => { pos => [ center => "center", 0, -0.3 ] },
      layout => [
         text => { color => "#FFFF00", font => "big" },
         $txt
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

