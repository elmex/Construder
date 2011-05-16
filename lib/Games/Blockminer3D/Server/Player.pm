package Games::Blockminer3D::Server::Player;
use common::sense;
use AnyEvent;
use Games::Blockminer3D::Server::World;
use Games::Blockminer3D::Vector;
use base qw/Object::Event/;
use Scalar::Util qw/weaken/;

=head1 NAME

Games::Blockminer3D::Server::Player - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Server::Player->new (%args)

=cut

my $PL_VIS_RAD = 2.6;

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;
   $self->{pos} = [0, 0, 0];

   return $self
}

sub _check_file {
   my ($self) = @_;
   my $pld = $Games::Blockminer3D::Server::Resources::PLAYERDIR;
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
      health    => 100,
      bio_e     => 100,
      happyness => 100,
      score     => 0,
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
   my $pld = $Games::Blockminer3D::Server::Resources::PLAYERDIR;
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

      warn "saved player $self->{name}.\n";

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
   $self->{hud1_tmr} = AE::timer 0, 0.5, sub {
      $wself->update_hud_1;
   };
   $self->{save_timer} = AE::timer 0, 30, sub {
      $wself->save;
   };
   $self->send_visible_chunks;
   #$self->teleport ([30, 2, 30]);
}

sub logout {
   my ($self) = @_;
   $self->save;
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

   my $opos = $self->{pos};
   $self->{pos} = $pos;

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

   my $plchnk = world_pos2chnkpos ($self->{pos});
   my $divvec = vsub ($chnk, $plchnk);
   return if vlength ($divvec) >= $PL_VIS_RAD;

   $self->send_chunk ($chnk);
}

sub send_visible_chunks {
   my ($self) = @_;

   $self->send_client ({ cmd => "chunk_upd_start" });

   my @chnks = _visible_chunks ($self->{pos});
   $self->send_chunk ($_) for @chnks;

   warn "done sending " . scalar (@chnks) . " visible chunks.\n";
   $self->send_client ({ cmd => "chunk_upd_done" });
}

sub send_chunk {
   my ($self, $chnk) = @_;

   # only send chunk when allcoated, in all other cases the chunk will
   # be sent by the chunk_changed-callback by the server (when it checks
   # whether any player might be interested in that chunk).
   my $data = Games::Blockminer3D::World::get_chunk_data (@$chnk);
   return unless defined $data;
   $self->send_client ({ cmd => "chunk", pos => $chnk }, $data);
}

sub update_hud_1 {
   my ($self) = @_;

   $self->send_client ({ cmd => activate_ui => ui => "player_hud_1", desc => {
      window => {
         sticky => 1,
         extents => [right => down => 0.3, 0.3],
         alpha => 0.8,
         color => "#000000",
      },
      elements => [
         {
            type => "text", extents => ["left", 0.02, 0.03, "font_height"],
            font => "small", color => "#ffffff",
            text => "Pos:" . sprintf ("%3.2f/%3.2f/%3.2f", @{$self->{pos}})
         },
         {
            type => "text", extents => ["left", "bottom_of 0", 0.03, 1],
            font => "small", color => "#ff0000",
            text => "(Press F1 for Help)"
         },
      ],
      commands => {
         default_keys => {
            f1 => "help",
            i  => "inventory",
            f9 => "teleport_home",
            f12 => "exit_server",
         },
      },
   } });
}

sub show_inventory {
   my ($self) = @_;

   my @listing;
   my $res = $Games::Blockminer3D::Server::RES;
   for (keys %{$self->{inventory}->{material}}) {
      my $m = $self->{inventory}->{material}->{$_};
      my $o = $res->get_object_by_type ($_);
      push @listing, [$o->{name}, $m];
   }

   warn "INVEN\n";

   $self->send_client ({ cmd => activate_ui => ui => "player_inventory", desc => {
      window => {
         extents => [center => center => 0.8, 0.9],
         alpha => 1,
         color => "#000000",
         prio => 100,
      },
      elements => [
         {
            type => "text", extents => ["center", 0.01, 0.9, "font_height"],
            font => "big", color => "#ffffff",
            align => "center",
            text => "Material:"
         },
         {
            type => "text", extents => ["left", "bottom_of 0", 0.4, 0.9],
            font => "normal", color => "#ffffff",
            align => "right",
            text => join ("\n", map { $_->[0] } @listing)
         },
         {
            type => "text", extents => ["right", "bottom_of 0", 0.5, 0.9],
            font => "normal", color => "#ff00ff",
            text => join ("\n", map { $_->[1] } @listing)
         }
      ]
   } });
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
   });

   my $tmr;
   $tmr = AE::timer 1, 0, sub {
      world_mutate_at ($pos, sub {
         my ($data) = @_;
         $data->[0] = 2;
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
         my $obj = $Games::Blockminer3D::Server::RES->get_object_by_type ($data->[0]);
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

   $self->send_client ({ cmd => "place_player", pos => $pos });
}

sub ui_res : event_cb {
   my ($self, $ui, $cmd, $arg) = @_;
   if ($ui eq 'player_hud_1') {
      if ($cmd eq 'inventory') {
         $self->show_inventory;
      } elsif ($cmd eq 'help') {
         $self->show_help;
      } elsif ($cmd eq 'teleport_home') {
         $self->teleport ([0, 0, 0]);
      } elsif ($cmd eq 'exit_server') {
         exit;
      }
   }
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
