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
   $self->{hud1_tmr} = AE::timer 0, 0.7, sub {
      $self->update_hud_1;
   };
   $self->teleport ([5, 15, 5]);
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
               last LASTUP;
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
           text => "Pos: @{$self->{pos}}"
         }
      ],
      commands => {
         default_keys => {
            r => "rere",
         },
      },
   } });
}

sub send_chunk {
   my ($self, $chnk) = @_;
   world_get_chunk_data ($chnk, sub {
      $self->send_client ({ cmd => "chunk", pos => $chnk }, $_[0]);
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
      }
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
