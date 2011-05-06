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
   $self->teleport ([30, 32, 30]);
}

sub update_pos {
   my ($self, $pos) = @_;

   $self->{pos} = $pos;

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

sub update_hud_1 {
   my ($self) = @_;

   $self->send_client ({ cmd => activate_ui => ui => "player_hud_1", desc => {
      window => {
         sticky => 1,
         extents => [right => down => 0.3, 0.3],
         alpha => 1,
         color => "#440011",
      },
      elements => [
         { type => "text", extents => ["center", "center", 0.5, 0.5],
            font => "normal", color => "#000000",
           text => "Cnt: " . $self->{cnt}
         },
         { type => "text", extents => ["center", 0.6, 0.5, 0.4],
            font => "small", color => "#000000",
           text => "Pos: " . vstr ($self->{pos})
         }
      ],
      commands => {
         default_keys => {
            r => "rere",
            i => "inventory",
         },
      },
   } });
}

sub show_inventory {
   my ($self) = @_;

   warn "HSOW INV\n";
   $self->send_client ({ cmd => activate_ui => ui => "player_inventory", desc => {
      window => {
         extents => [center => center => 0.8, 0.8],
         alpha => 1,
         color => "#005500",
         prio => 100,
      },
      elements => [
         {
            type => "text", extents => ["center", 0.01, 0.9, "line_height"],
            font => "big", color => "#ffffff",
            text => "Material:"
         },
         {
            type => "text", extents => ["left", "bottom_of 1", 0.9, 0.01],
            font => "big", color => "#ffffff",
            text => "Test"
         },
      ]
   } });
}

sub start_dematerialize {
   my ($self, $pos) = @_;

   my $id = world_pos2id ($pos);
   if ($self->{dematerializings}->{$id}) {
      return;
   }

   $self->send_client ({ cmd => "highlight", pos => $pos, color => [1, 0, 1], fade => 1.5 });
   $self->{dematerializings}->{$id} = 1;

   my $tmr;
   $tmr = AE::timer 1.5, 0, sub {
      world_mutate_at ($pos, sub {
         my ($data) = @_;
         $self->{inventory}->{material}->[$data->[0]]++;
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

sub send_chunk {
   my ($self, $chnk) = @_;
   world_get_chunk_data ($chnk, sub {
      $self->send_client ({ cmd => "chunk", pos => $chnk }, $_[0]);
      $self->{chunk_sending} = 0;
   });
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
      if ($cmd eq 'rere') {
         $self->{cnt}++;
         $self->update_hud_1;
      } elsif ($cmd eq 'inventory') {
         $self->show_inventory;
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
