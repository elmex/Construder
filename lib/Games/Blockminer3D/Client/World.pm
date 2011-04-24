package Games::Blockminer3D::Client::World;
use common::sense;
use Math::VectorReal;

=head1 NAME

Games::Blockminer3D::Client::World - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

my @CHUNKS;

sub set_chunk {
   my ($x, $y, $z, $chunk) = @_;
   warn "set chunk: $x $y $z $chunk\n";
   ($x, $y, $z) = (
      int ($x / $Games::Blockminer3D::Client::MapChunk::SIZE),
      int ($y / $Games::Blockminer3D::Client::MapChunk::SIZE),
      int ($z / $Games::Blockminer3D::Client::MapChunk::SIZE),
   );
   my $quadr =
        ($x < 0 ? 0x1 : 0)
      | ($y < 0 ? 0x2 : 0)
      | ($z < 0 ? 0x4 : 0);
   $CHUNKS[$quadr]->[$x]->[$y]->[$z] = $chunk;
}

sub get_chunk {
   my ($x, $y, $z) = @_;
   ($x, $y, $z) = (0, 0, 0);
   ($x, $y, $z) = (
      int ($x / $Games::Blockminer3D::Client::MapChunk::SIZE),
      int ($y / $Games::Blockminer3D::Client::MapChunk::SIZE),
      int ($z / $Games::Blockminer3D::Client::MapChunk::SIZE),
   );
   my $quadr =
        ($x < 0 ? 0x1 : 0)
      | ($y < 0 ? 0x2 : 0)
      | ($z < 0 ? 0x4 : 0);
   $CHUNKS[$quadr]->[$x]->[$y]->[$z]
}

sub get_pos {
   my ($x, $y, $z) = @_;
   $x = int ($x - $Games::Blockminer3D::Client::MapChunk::SIZE * int ($x / $Games::Blockminer3D::Client::MapChunk::SIZE));
   $y = int ($y - $Games::Blockminer3D::Client::MapChunk::SIZE * int ($y / $Games::Blockminer3D::Client::MapChunk::SIZE));
   $z = int ($z - $Games::Blockminer3D::Client::MapChunk::SIZE * int ($z / $Games::Blockminer3D::Client::MapChunk::SIZE));
   my $chnk = get_chunk ($x, $y, $z);
   unless ($chnk) {
      return ['X', 20, 0]; # invisible block
   }
   $chnk->{map}->[$x]->[$y]->[$z]
}
sub collide {
}

sub visible_quads {
   my ($x, $y, $z) = @_;

   my ($cur_chnk) = [
      int ($x / $Games::Blockminer3D::Client::MapChunk::SIZE),
      int ($y / $Games::Blockminer3D::Client::MapChunk::SIZE),
      int ($z / $Games::Blockminer3D::Client::MapChunk::SIZE),
   ];

   my @quads;

   for my $dcx (-1..1) {
      for my $dcy (-1..1) {
         for my $dcz (-1..1) {
            my ($cx, $cy, $cz) = (
               $cur_chnk->[0] + $dcx,
               $cur_chnk->[1] + $dcy,
               $cur_chnk->[2] + $dcz
            );
            my $chnk = get_chunk ($cx, $cy, $cz);
            warn "CHUNK $cx, $cy, $cz: $chnk\n";
            next unless defined $chnk;
            push @quads, map {
               [
                  [
                     $_->[0]->[0] + ($cx * $Games::Blockminer3D::Client::MapChunk::SIZE),
                     $_->[0]->[1] + ($cy * $Games::Blockminer3D::Client::MapChunk::SIZE),
                     $_->[0]->[2] + ($cz * $Games::Blockminer3D::Client::MapChunk::SIZE),
                  ],
                  $_->[1],
                  $_->[2],
                  $_->[3],
               ]
            } $chnk->visible_quads;
         }
      }
   }
   warn "QUADS: " . scalar (@quads) . "\n";

   @quads
}

sub _closest_pt_point_aabb {
   my ($pt, $box_min, $box_max) = @_;
   my @pt      = $pt->array;
   my @box_min = $box_min->array;
   my @box_max = $box_max->array;
   my @out;
   for (0..2) {
      my $pv = $pt[$_];
      my ($bmin, $bmax) = ($box_min[$_], $box_max[$_]);
      if ($bmin > $bmax) { $bmax = $box_min[$_]; $bmin = $box_max[$_] }
      $pv = $bmin if $pv < $bmin;
      $pv = $bmax if $pv > $bmax;
      push @out, $pv;
   }
   (vector (@out))
}

sub _collide_box {
   my ($box, $pos) = @_;
   my $max = $box + vector (1, 1, 1);
   my ($abpt) = _closest_pt_point_aabb ($pos, $box, $max);
   my $dv = $pos - $abpt;
   #d#warn "aabb: $pos, $abpt, $dv\n";
   return ($dv, $abpt)
}

sub _is_solid_box {
   my ($map, $box) = @_;
   my $b = _map_get_if_exists ($map, $box->array);
   $b->[2] && $b->[0] ne ' '
}

# collide sphere at $pos with radius $rad
sub collide {
   my ($pos, $rad, $rcoll, $rec, $orig_pos) = @_;

   if ($rec > 8) {
      return ($orig_pos);
   }

   $orig_pos = $pos unless defined $orig_pos;

   # find the 6 adjacent blocks
   # and check:
   #   bottom of top
   #   top of bottom
   #   and the interiors of the 4 adjacent blocks

   # the "current" block
   my $my_box = vector (int $pos->x, int $pos->y, int $pos->z);

   for my $x (-1..1) {
      for my $y (-1..1) {
         for my $z (-1..1) {
            my $cur_box = $my_box + vector ($x, $y, $z);
            my $bx = get_pos ($cur_box->array);
            next unless $bx->[2] && $bx->[0] ne ' ';
            my ($dv, $ipt) = _collide_box ($cur_box, $pos);
            warn "solid box at $cur_box, dist vec $dv |"
                 . (sprintf "%9.4f", $dv->length)
                 . "|, coll point $ipt\n";
            if ($dv->length == 0) { # ouch, directly in the side?
               $$rcoll = vector (0, 0, 0);
               warn "player landed directly on the surface\n";
               return ($orig_pos);
            }
            if ($dv->length < $rad) {
               my $back_dist = ($rad - $dv->length) + 0.00001;
               my $new_pos = $pos + ($dv->norm * $back_dist);
               if ($$rcoll) {
                  $$rcoll += $dv;
               } else {
                  $$rcoll = $dv;
               }
               warn "recollide pos $new_pos, vector $$rcoll\n";
               return collide ($new_pos, $rad, $rcoll, $rec + 1);
            }
         }
      }
   }

   return ($pos);
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

