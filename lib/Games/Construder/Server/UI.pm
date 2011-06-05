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
         delete $self->{upd_score_hl_tmout};
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
   $self->{msg_tout} = AE::timer (($error ? 3 : 1), 0, sub {
      $wself->hide;
      delete $self->{msg_tout};
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
      t   => "location_book",
      e   => "interact",
   )
}

sub handle_command {
   my ($self, $cmd, $arg, $pos) = @_;

   my $pl = $self->{pl};

   if ($cmd eq 'inventory') {
      $pl->show_inventory;
   } elsif ($cmd eq 'location_book') {
      $pl->show_location_book;
   } elsif ($cmd eq 'sector_finder') {
      $pl->show_sector_finder;
   } elsif ($cmd eq 'cheat') {
      $pl->show_cheat_dialog;
   } elsif ($cmd eq 'help') {
      $pl->show_help;
   } elsif ($cmd eq 'teleport_home') {
      $pl->teleport ([0, 0, 0]);
   } elsif ($cmd eq 'interact') {
      $pl->interact ($pos->[0]);
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

   my $sinfo = $Games::Construder::Server::CHNK->sector_info (@$chnk_pos);

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

package Games::Construder::Server::UI::Inventory;

use base qw/Games::Construder::Server::UI/;

sub commands {
}

sub layout {
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

