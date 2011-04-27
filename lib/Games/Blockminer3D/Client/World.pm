package Games::Blockminer3D::Client::World;
use common::sense;
use Games::Blockminer3D::Vector;
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
   my ($pos, $chunk) = @_;
   warn "set chunk: @$pos $chunk\n";
   my ($x, $y, $z) =
      @{vfloor (vsdiv ($pos, $Games::Blockminer3D::Client::MapChunk::SIZE))};
   my $quadr = ($x < 0 ? 0x1 : 0) | ($y < 0 ? 0x2 : 0) | ($z < 0 ? 0x4 : 0);
   $CHUNKS[$quadr]->[$x]->[$y]->[$z] = $chunk;
}

sub get_chunk {
   my ($pos) = @_;
   $pos = [0, 0, 0];
   my ($x, $y, $z) =
      @{vfloor (vsdiv ($pos, $Games::Blockminer3D::Client::MapChunk::SIZE))};
   my $quadr = ($x < 0 ? 0x1 : 0) | ($y < 0 ? 0x2 : 0) | ($z < 0 ? 0x4 : 0);
   $CHUNKS[$quadr]->[$x]->[$y]->[$z]
}

sub get_pos {
   my ($pos) = @_;
   my $opos = [@$pos];
   $pos = vsubd ($pos,
      $Games::Blockminer3D::Client::MapChunk::SIZE
         * int ($pos->[0] / $Games::Blockminer3D::Client::MapChunk::SIZE),
      $Games::Blockminer3D::Client::MapChunk::SIZE
         * int ($pos->[1] / $Games::Blockminer3D::Client::MapChunk::SIZE),
      $Games::Blockminer3D::Client::MapChunk::SIZE
         * int ($pos->[2] / $Games::Blockminer3D::Client::MapChunk::SIZE)
   );
   @$pos = map +(int ($_)), @$pos;
   my $chnk = get_chunk ($opos);
   unless ($chnk) {
      return ['X', 20, 0]; # invisible block
   }
   $chnk->{map}->[$pos->[0]]->[$pos->[1]]->[$pos->[2]]
}

sub _closest_pt_point_aabb_2d {
   my ($pt, $box_min, $box_max) = @_;
   my @out;
   for (0..1) {
      my $pv = $pt->[$_];
      my ($bmin, $bmax) = ($box_min->[$_], $box_max->[$_]);
      if ($bmin > $bmax) { $bmax = $box_min->[$_]; $bmin = $box_max->[$_] }
      $pv = $bmin if $pv < $bmin;
      $pv = $bmax if $pv > $bmax;
      push @out, $pv;
   }
   \@out
}

sub _closest_pt_point_aabb {
   my ($pt, $box_min, $box_max) = @_;
   my @out;
   for (0..2) {
      my $pv = $pt->[$_];
      my ($bmin, $bmax) = ($box_min->[$_], $box_max->[$_]);
      if ($bmin > $bmax) { $bmax = $box_min->[$_]; $bmin = $box_max->[$_] }
      $pv = $bmin if $pv < $bmin;
      $pv = $bmax if $pv > $bmax;
      push @out, $pv;
   }
   \@out
}

sub _collide_sphere_box {
   my ($sphere_pos, $sphere_rad, $box) = @_;

   my $abpt = _closest_pt_point_aabb ($sphere_pos, $box, vaddd ($box, 1, 1, 1));
   my $dv   = vsub ($sphere_pos, $abpt);

   #d#warn "solid box at $cur_box, dist vec $dv |"
   #d#     . (sprintf "%9.4f", $dv->length) . "\n";

   my $dvlen = vlength ($dv);

   if ($dvlen == 0) { # ouch, directly in the side?
      warn "player landed directly on the surface\n";
      return ([0, 0, 0]);
   }

   if ($dvlen < $sphere_rad) {
      my $back_dist = ($sphere_rad - $dvlen) + 0.00001;
      return ($dv, vsmul (vnorm ($dv, $dvlen), $back_dist));
   }

   return ()
}

sub is_solid_box { $_[0]->[2] && $_[0]->[0] ne ' ' }

sub collide_cylinder_aabb {
   my ($pos, $height, $radius, $rcollide_normal, $recursion, $original_pos) = @_;

   # we collide too much:
   if ($recursion > 5) {
      warn "collision occured on too many things. we couldn't backoff!";
      return ($original_pos); # found position is as good as any...
   }
   #d# warn "collide at " . vstr ($pos) . "\n";

   $original_pos = [@$pos] unless $original_pos;

   # the "current" block
   my $head_pos = vaddd ($pos, 0, $height, 0);
   my $head_box = vfloor ($head_pos);

   my $hbox = get_pos ($head_box);
   if (is_solid_box ($hbox)) {
      $$rcollide_normal = vaccum ($$rcollide_normal, [0, -1, 0]);
      my $new_pos =
         vaddd ($pos, 0, -(($head_pos->[1] - $head_box->[1]) + 0.001), 0);
      return collide_cylinder_aabb (
         $new_pos, $height, $radius, $rcollide_normal, $recursion + 1, $original_pos);
   }

   my $foot_box = vfloor ($pos);
   my $fbox = get_pos ($foot_box);
   if (is_solid_box ($fbox)) {
      my $box_y = $foot_box->[1] + 1;
      $$rcollide_normal = vaccum ($$rcollide_normal, [0, 1, 0]);
      my $new_pos = vaddd ($pos, 0, ($box_y - $pos->[1]) + 0.001, 0);
      return collide_cylinder_aabb (
         $new_pos, $height, $radius, $rcollide_normal, $recursion + 1, $original_pos);
   }

   # find quadrant:
   my (@xr, @yr, @zr);
   (@yr) = (0, 1, 2);
   my ($ax, $az) = (
      abs ($pos->[0] - int $pos->[0]),
      abs ($pos->[2] - int $pos->[2])
   );
   push @xr, $ax > 0.5 ? (0, 1) : (0, -1);
   push @zr, $az > 0.5 ? (0, 1) : (0, -1);
   $xr[1] *= -1 if $pos->[0] < 0;
   $zr[1] *= -1 if $pos->[2] < 0;

   # now check if we collide in the X and Z plane with any of the boxes
   my $pos_2d = [$pos->[0], $pos->[2]];
   #warn "no head or food collision, checking " . vstr ($pos_2d) . "\n";

   for my $y ($foot_box->[1]..$head_box->[1]) {
      for my $dx (@xr) {
         for my $dz (@zr) {
            my ($x, $z) = ($foot_box->[0] + $dx, $foot_box->[2] + $dz);
            my $sbox = get_pos ([$x, $y, $z]);

            if (is_solid_box ($sbox)) {
               my $aabb_pt = _closest_pt_point_aabb_2d (
                  $pos_2d, [$x, $z], [$x + 1, $z + 1]);

               my $dvec = vsub_2d ($pos_2d, $aabb_pt);
               my $dvecl = vlength_2d ($dvec);
               #d# warn "coll point $x $y $z: "
               #d#      . vstr ($aabb_pt) . " pl "
               #d#      . vstr ($pos_2d) . " dv "
               #d#      . vstr ($dvec) . " ($dvecl)\n";

               if ($dvecl == 0) {
                  $$rcollide_normal = [0, 1, 0];
                  #d# warn "collision happened INSIDE something!\n";
                  my $new_pos = vaddd ($pos, 0, 1, 0);
                  return collide_cylinder_aabb (
                     $new_pos, $height, $radius, $rcollide_normal,
                     $recursion + 1, $original_pos);
               }

               if ($dvecl < $radius) {
                  my $backoff_dist = ($radius - $dvecl) + 0.0001;

                  my $vn = vnorm ([$dvec->[0], 0, $dvec->[1]]);
                  #d# warn "backoff: $backoff_dist into " . vstr ($vn) . "\n";
                  $$rcollide_normal = vaccum ($$rcollide_normal, $vn);
                  my $new_pos = vadd ($pos, vsmul ($vn, $backoff_dist));
                  return collide_cylinder_aabb (
                     $new_pos, $height, $radius, $rcollide_normal,
                     $recursion + 1, $original_pos);
               }
            }
         }
      }
   }

   return $pos;

   # rough algo:
   # check if feet $pos is inside blocking box
   #   => move up
   # check if head is inside blocking box
   #   => move down
   # check if any of the adjacent boxes not (9 boxes at max)
   #      in the Y coord of the $pos collide
   #      with the $radius of the cylinder
   #   => if so, move away by direction given
   #      from XZ aabb-point to XZ $pos

   #warn "collide player at " . vstr ($original_pos)
   #     . ", in box " . vstr ($my_box) . "\n";
   #for my $x (@xr) {
   #   for my $y (@yr) {
   #      for my $z (@zr) {
   #         my $cur_box = vaddd ($my_box, $x, $y, $z);
   #         my $bx = get_pos ($cur_box);
   #         next unless $bx->[2] && $bx->[0] ne ' ';
   #         warn "checking box at " . vstr ($cur_box) . "\n";
   #      }
   #   }
   #}
}

# collide sphere at $pos with radius $rad
#   0.00059 secsPcoll in flight without collisions
#   0.00171secsPcoll to 0.00154secsPcoll when colliding with floor
# after own vector math module:
#   0.00032 secsPcoll in flight
#   0.00068 secsPcoll on floor  # i find this amazing!
sub collide {
   my ($pos, $rad, $rcoll, $rec, $orig_pos) = @_;

   if ($rec > 8) {
      return ($orig_pos);
   }

   $orig_pos = [@$pos] unless defined $orig_pos;

   # find the 6 adjacent blocks
   # and check:
   #   bottom of top
   #   top of bottom
   #   and the interiors of the 4 adjacent blocks

   # usually i should just check the 4 adjacent blocks instead of the 27.
   # i need to check the quadrant the sphere is in
   #
   # there are 8 quadrants $pos can be in:
   #
   #       -------------
   #      /.    /     /|
   #     / .   /     / |
   #    /-----------/  |
   #   /   . /     /|  |
   #  /    ./     / | /|
   # -------------  |/ |
   # |    .|. . .| ./ .|
   # |   . |     | /| /
   # |-----|-----|/ |/
   # | .   |     |  /
   # |.    |     | /
   # |-----------|/

   for my $sphere (ref $rad ? @$rad : [[0,0,0],$rad]) {
      my ($spos, $srad) = @$sphere;
      $spos = vadd ($spos, $pos),

      # the "current" block
      my $my_box = vfloor ($spos);

      my (@xr, @yr, @zr);
      my ($ax, $ay, $az) = (
         abs ($spos->[0] - int $spos->[0]),
         abs ($spos->[1] - int $spos->[1]),
         abs ($spos->[2] - int $spos->[2])
      );
      push @xr, $ax > 0.5 ? (0, 1) : (0, -1);
      push @yr, $ay > 0.5 ? (0, 1) : (0, -1);
      push @zr, $az > 0.5 ? (0, 1) : (0, -1);
      $xr[1] *= -1 if $spos->[0] < 0;
      $yr[1] *= -1 if $spos->[1] < 0;
      $zr[1] *= -1 if $spos->[2] < 0;

      #d# warn "sphere pos @$spos: checking [@xr|@yr|@zr]\n";

      for my $x (@xr) {
         for my $y (@yr) {
            for my $z (@zr) {
               my $cur_box = vaddd ($my_box, $x, $y, $z);
               my $bx = get_pos ($cur_box);
               next unless $bx->[2] && $bx->[0] ne ' ';

               my ($col_dir, $pos_adj) = _collide_sphere_box ($spos, $srad, $cur_box);
               if ($col_dir) { # collided!
                  if (defined $$rcoll && defined $pos_adj) {
                     $$rcoll += $col_dir;
                  } else {
                     $$rcoll = $col_dir;
                  }

                  if (defined $pos_adj) { # was able to move to safer location?
                     return collide (
                              vadd ($pos, $pos_adj),
                              $rad,  $rcoll, $rec + 1, $orig_pos);

                  } else { # collided with something, but unable to move to safe location
                     warn "player collided with something, but we couldn't repell him!";
                     return ($orig_pos);
                  }
               }
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

