package Games::Blockminer3D::Client::MapChunk;
use common::sense;

use base qw/Object::Event/;

=head1 NAME

Games::Blockminer3D::Client::MapChunk - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

A chunk of the Blockminer3D world.

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Client::MapChunk->new (%args)

=cut

our ($SIZE) = 12;

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;

   return $self
}

sub _map_get_if_exists {
   my ($map, $x, $y, $z) = @_;
   return [0, 16, 1] if $x < 0     || $y < 0     || $z < 0;
   return [0, 16, 1] if $x >= $SIZE || $y >= $SIZE || $z >= $SIZE;
   $map->[$x]->[$y]->[$z]
}

sub _neighbours {
   my ($map, $x, $y, $z) = @_;
 #  my ($cur, $top, $bot, $left, $right, $front, $back) 
   my @n = (
      _map_get_if_exists ($map, $x, $y,     $z),
      _map_get_if_exists ($map, $x, $y + 1, $z),
      _map_get_if_exists ($map, $x, $y - 1, $z),
      _map_get_if_exists ($map, $x - 1, $y, $z),
      _map_get_if_exists ($map, $x + 1, $y, $z),
      _map_get_if_exists ($map, $x, $y,     $z - 1),
      _map_get_if_exists ($map, $x, $y,     $z + 1),
   );
   @n
}

sub _data2array {
   my ($dat) = @_;
   my ($blk, $meta, $add) = unpack "nCC", $dat;
   my ($type, $light) = (($blk & 0xFFF0) >> 4, ($blk & 0x000F));
   [$type, $light, $meta, $add]
}

sub data_fill {
   my ($self, $data) = @_;

   my $map = [];
   for (my $x = 0; $x < $SIZE; $x++) {
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $z = 0; $z < $SIZE; $z++) {
            my $chnk_offs = $x + $y * $SIZE + $z * ($SIZE ** 2);
            $map->[$x]->[$y]->[$z] = _data2array (substr $data, $chnk_offs * 4, 4);
            #d#warn "DATAFILL: $x,$y,$z: " . JSON->new->encode ($map->[$x]->[$y]->[$z]) . "\n";
         }
      }
   }

   my $visible;
   for (my $x = 0; $x < $SIZE; $x++) {
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $z = 0; $z < $SIZE; $z++) {
            my ($cur, $top, $bot, $left, $right, $front, $back)
               = _neighbours ($map, $x, $y, $z);
            my $cnt = 0;
            $cnt++ if $top->[0]   == 0;
            $cnt++ if $bot->[0]   == 0;
            $cnt++ if $left->[0]  == 0;
            $cnt++ if $right->[0] == 0;
            $cnt++ if $front->[0] == 0;
            $cnt++ if $back->[0]  == 0;

            if ($cnt == 0
                && not (
                   $x == 0 || $x == $SIZE - 1
                   || $y == 0 || $y == $SIZE - 1
                   || $z == 0 || $z == $SIZE - 1)
            ) {
               $cur->[2] = 0;
 #              $map->[$x]->[$y]->[$z] = [1, 16, 1];
            } else {
               $cur->[2] = 1;
               $visible++;
            }
         }
      }
   }
   warn "VISIBLE: $visible\n";

   $self->{map} = $map;
}

sub cube_fill {
   my ($self) = @_;

   my $map = [];
   for (my $x = 0; $x < $SIZE; $x++) {
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $z = 0; $z < $SIZE; $z++) {
            if ($x == 0 || $y == 0 || $z == 0
                || ($z == ($SIZE - 1))
                || ($x == ($SIZE - 1))
                || ($y == ($SIZE - 1))
            ) {
               $map->[$x]->[$y]->[$z] = [1, 16, 1];
            } else {
               $map->[$x]->[$y]->[$z] = [0, 16, 1];
            }
         }
      }
   }
   $map->[5]->[1]->[7] = [2, 10, 1, 2];
   $map->[6]->[2]->[7] = [2, 10, 1, 2];
   $map->[7]->[3]->[7] = [2, 10, 1, 2];
   $map->[8]->[4]->[7] = [2, 10, 1, 2];
   $map->[9]->[5]->[7] = [2, 10, 1, 2];
   $map->[1]->[1]->[1] = [1, 10, 1];
   $map->[2]->[2]->[2] = [1, 10, 1];
   $map->[1]->[3]->[1] = [1, 10, 1];
   $map->[3]->[3]->[3] = [1, 10, 1];
   $self->{map} = $map;
}

sub visible_quads {
   my ($self, $offs) = @_;
   if ($self->{quads_cache}) {
      return @{$self->{quads_cache}}
   }

   my $map = $self->{map};

   my @quads;
   for (my $x = 0; $x < $SIZE; $x++) {
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $z = 0; $z < $SIZE; $z++) {
            my ($cur, $top, $bot, $left, $right, $front, $back)
               = _neighbours ($map, $x, $y, $z);
            next unless $cur->[2];
            if ($cur->[0] != 0) {
               my @faces;

               if ($front->[2] && $front->[0] == 0) {
                  push @faces, 0
               }
               if ($top->[2] && $top->[0] == 0) {
                  push @faces, 1
               }
               if ($back->[2] && $back->[0] == 0) {
                  push @faces, 2
               }
               if ($left->[2] && $left->[0] == 0) {
                  push @faces, 3
               }
               if ($right->[2] && $right->[0] == 0) {
                  push @faces, 4
               }
               if ($bot->[2] && $bot->[0] == 0) {
                  push @faces, 5
               }

              # my ($pos, $faces, $light, $tex) = @$_;
               #d# warn "QUAD: @faces at $x, $y, $z ($cur->[1])\n";
               push @quads, [
                  [$x, $y, $z], # pos
                  \@faces,      # faces
                  $cur->[1],    # light
                  $cur->[3]     # texture!?
                     ? $cur->[3]
                     : ($cur->[0] != 0 ? 1 : 0)
               ];
            }
         }
      }
   }
   $self->{quads_cache} = \@quads;
   @quads
}

sub chunk_changed : event_cb {
   my ($self) = @_;
   delete $self->{quads_cache};
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

