package Games::Blockminer3D::Server::Player;
use common::sense;
use AnyEvent;
use Games::Blockminer3D::Server::World;
use Games::Blockminer3D::Vector;
use base qw/Object::Event/;

=head1 NAME

Games::Blockminer3D::Server::Player - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Server::Player->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;

   return $self
}

sub init {
   my ($self) = @_;
   $self->{hud1_tmr} = AE::timer 0, 0.5, sub {
      $self->update_hud_1;
   };
   $self->teleport ([30, 2, 30]);
}

sub update_pos {
   my ($self, $pos) = @_;

   $self->{pos} = $pos;

   # keep track of chunk changes and maintain a generation counter
   # this function then synchronizes the client's chunks with the
   # generation counter of the current visible chunks and possibly
   # sends an update or generates the chunks

   # the server needs to query all players for changed chunks and
   # see whether some player sees the changed chunks and actively
   # sends a chunk update himself

   # sector module will be dumped
   # world module is responsible for loading, generating and saving chunks

   my $chnk = world_pos2chnkpos ($pos);
   my $old_state = $self->{chunk_state};
   my $chunk_state = {};
   LASTUP:
   for my $dx (0, -1, 1) {
      for my $dy (0, -1, 1) {
         for my $dz (0, -1, 1) {
            my $cur_chunk = vaddd ($chnk, $dx, $dy, $dz);
            my $id = world_pos2id ($cur_chunk);
            if ($old_state->{$id}) {
               $chunk_state->{$id} = delete $old_state->{$id};

            } else {
               $self->send_chunk ($cur_chunk);
               $chunk_state->{$id} = 1;
            }
         }
      }
   }
   $self->{chunk_state} = $chunk_state;
}

sub send_chunk {
   my ($self, $chnk) = @_;
   # only send chunk when allcoated, in all other cases the chunk will
   # be sent by the chunk_changed-callback by the server (when it checks
   # whether any player might be interested in that chunk).
   my $data = b3d_world_get_chunk_data (@$chnk);
   return unless defined $data;
   $self->send_client ({ cmd => "chunk", pos => $chnk }, $data);

   # TODO / FIXME: check the generation of the chunk here and store it!
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
   $self->send_client ({ cmd => activate_ui => ui => "player_inventory", desc => {
      window => {
         extents => [center => center => 0.8, 0.8],
         alpha => 1,
         color => "#444444",
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

      # FIXME: this is more or less a hack, we need some chunk update system soon
      my $tmr;
      $tmr = AE::timer 0, 0, sub {
         $self->send_chunk (world_pos2chnkpos ($pos)); # FIXME: send incremental updates pls
         undef $tmr;
      };
      return 1;
   });

   my $tmr;
   $tmr = AE::timer 1, 0, sub {
      world_mutate_at ($pos, sub {
         my ($data) = @_;
         $data->[0] = 2;

         # FIXME: this is more or less a hack, we need some chunk update system soon
         $tmr = AE::timer 0, 0, sub {
            $self->send_chunk (world_pos2chnkpos ($pos)); # FIXME: send incremental updates pls
            delete $self->{materializings}->{$id};
            undef $tmr;
         };
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
         $self->{inventory}->{material}->{$data->[0]}++;
         $data->[0] = 0;

         # FIXME: this is more or less a hack, we need some chunk update system soon
         $tmr = AE::timer 0, 0, sub {
            $self->send_chunk (world_pos2chnkpos ($pos)); # FIXME: send incremental updates pls
            delete $self->{dematerializings}->{$id};
         };
         return 1;
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
         $self->teleport ([30, 2, 30]);

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
