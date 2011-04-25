package Games::Blockminer3D::Client::World;
use common::sense;
use Math::VectorReal;
use POSIX qw/floor/;

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
      floor ($x / $Games::Blockminer3D::Client::MapChunk::SIZE),
      floor ($y / $Games::Blockminer3D::Client::MapChunk::SIZE),
      floor ($z / $Games::Blockminer3D::Client::MapChunk::SIZE),
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
      floor ($x / $Games::Blockminer3D::Client::MapChunk::SIZE),
      floor ($y / $Games::Blockminer3D::Client::MapChunk::SIZE),
      floor ($z / $Games::Blockminer3D::Client::MapChunk::SIZE),
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
   my $my_box = vector (floor ($pos->x), floor ($pos->y), floor ($pos->z));

   # usually i should just check the 4 adjacent blocks instead of the 27.
   # i need to check the quadrant the sphere is in
   #
   # there are 8 quadrants $pos can be in:
   #
   #      -------------
   #     /.     /     /|
   #    / .    /     / |
   #   /------------/  |
   #  /   .  /     /|  |
   # /    . /     / | /|
   # -------------  |/ |
   # |    .|. . .| ./ .|
   # |   . |     | /| /
   # |-----|-----|/ |/
   # | .   |     |  /
   # |.    |     | /
   # |-----------|/

   my (@xr, @yr, @zr);
   if (0) {
      (@xr) = (-1..1);
      (@yr) = (-1..1);
      (@zr) = (-1..1);
   } else {
      my ($ax, $ay, $az) = (
         abs ($pos->x - int $pos->x),
         abs ($pos->y - int $pos->y),
         abs ($pos->z - int $pos->z)
      );
      push @xr, $ax > 0.5 ? (0, 1) : (0, -1);
      push @yr, $ay > 0.5 ? (0, 1) : (0, -1);
      push @zr, $az > 0.5 ? (0, 1) : (0, -1);
      $xr[1] *= -1 if $pos->x < 0;
      $yr[1] *= -1 if $pos->y < 0;
      $zr[1] *= -1 if $pos->z < 0;
   }

   #d# warn "pos $pos: checking [@xr|@yr|@zr]\n";

   for my $x (@xr) {
      for my $y (@yr) {
         for my $z (@zr) {
            my $cur_box = $my_box + vector ($x, $y, $z);
            my $bx = get_pos ($cur_box->array);
            next unless $bx->[2] && $bx->[0] ne ' ';
            my ($dv, $ipt) = _collide_box ($cur_box, $pos);
            my $cb_max = $cur_box + vector (1, 1, 1);
            #d#warn "solid box at $cur_box (to $cb_max), dist vec $dv |"
            #d#     . (sprintf "%9.4f", $dv->length)
            #d#     . "|, coll point $ipt\n";
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
               #d#warn "recollide pos $new_pos, vector $$rcoll\n";
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

