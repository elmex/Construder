package Games::Blockminer3D::Client::World;
use common::sense;
use Games::Blockminer3D::Vector;
use POSIX qw/floor/;
use Object::Event;

require Exporter;
use POSIX qw/floor/;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   world_visible_chunks_at
   world_collide_cylinder_aabb
   world_is_solid_box
   world_intersect_ray_box
   world_get_box_at
   world_get_chunk world_get_chunk_at
   world_set_chunk
   world_change_chunk_at
   world_init
   world
/;

=head1 NAME

Games::Blockminer3D::Client::World - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

my @CHUNKS;

my $EVENT_SINGLETON = Object::Event->new;

sub world_init {
   $EVENT_SINGLETON->reg_cb (chunk_changed => sub {
      my ($e, $x, $y, $z) = @_;
      my $chunk = world_get_chunk ($x, $y, $z)
         or return;
      $chunk->chunk_changed;
   });
}

sub world { $EVENT_SINGLETON }

sub pos2chunk {
   @{vfloor (vsdiv ($_[0], $Games::Blockminer3D::Client::MapChunk::SIZE))};
}

sub world_change_chunk_at {
   my ($pos) = @_;
   world ()->event (chunk_changed => pos2chunk ($pos));
}

sub world_set_chunk {
   my ($cx, $cy, $cz, $chunk) = @_;
   warn "set chunk: $cx $cy $cz $chunk\n";
   my $q = ($cx < 0 ? 0x1 : 0) | ($cy < 0 ? 0x2 : 0) | ($cz < 0 ? 0x4 : 0);
   $CHUNKS[$q]->[abs $cx]->[abs $cy]->[abs $cz] = $chunk;
}

sub world_get_chunk {
   my ($cx, $cy, $cz) = @_;
   my $q = ($cx < 0 ? 0x1 : 0) | ($cy < 0 ? 0x2 : 0) | ($cz < 0 ? 0x4 : 0);
   $CHUNKS[$q]->[abs $cx]->[abs $cy]->[abs $cz]
}

sub world_get_chunk_at {
   my ($pos) = @_;
   my (@chnkp) = pos2chunk ($pos);
   world_get_chunk (@chnkp)
}

sub world_get_box_at {
   my ($pos) = @_;

   my ($cx, $cy, $cz) = pos2chunk ($pos);
   my $chnk = world_get_chunk ($cx, $cy, $cz);
   unless ($chnk) {
      return ['X', 20, 0]; # invisible block
   }

   my $npos = vsubd ($pos,
      $cx * $Games::Blockminer3D::Client::MapChunk::SIZE,
      $cy * $Games::Blockminer3D::Client::MapChunk::SIZE,
      $cz * $Games::Blockminer3D::Client::MapChunk::SIZE
   );
   vifloor ($npos);
   $chnk->{map}->[$npos->[0]]->[$npos->[1]]->[$npos->[2]]
}

sub world_intersect_ray_box {
   my ($pos, $dir, $bmi) = @_;

   my $bma = vaddd ($bmi, 1, 1, 1);

   my $tmin = -9999.99;
   my $tmax = 9999.99; # arbitrary max distance :->

   #d#warn "IRFAY pos ".vstr($pos)." dir " . vstr ($dir)
   #d#     . " bmi " .vstr ($bmi) . "-".vstr($bma)."\n";

   for my $i (0..2) {
      if (abs ($dir->[$i]) < 0.01) { # parallel to an axis?
         return if
               $pos->[$i] < $bmi->[$i]
            || $pos->[$i] > $bma->[$i];

      } else {
         my $ood = 1.0 / $dir->[$i];
         my $t1 = ($bmi->[$i] - $pos->[$i]) * $ood;
         my $t2 = ($bma->[$i] - $pos->[$i]) * $ood;
         #d# warn "T1[$i] $t1 T2 $t2 TMIN $tmin TMAX $tmax\n";

         ($t1, $t2) = ($t2, $t1) if $t1 > $t2;
         #d# warn "BT1[$i] $t1 T2 $t2 TMIN $tmin TMAX $tmax\n";
         $tmin = $t1 if $t1 > $tmin;
         $tmax = $t2 if $t2 < $tmax;

         return if $tmin > $tmax; # no intersection anymore!
      }
   }

   #d# warn "OUTPUT $tmin: " . vstr (vadd ($pos, vsmul ($dir, $tmin))) . "\n";
   return ($tmin, vadd ($pos, vsmul ($dir, $tmin))); # return intersection position!
}

sub world_visible_chunks_at {
   my ($pos) = @_;
   my (@chunk_pos) = pos2chunk ($pos);

   my @chnkposes;
   for my $dx (0, -1, 1) {
      for my $dy (0, -1, 1) {
         for my $dz (0, -1, 1) {
            push @chnkposes, vaddd (\@chunk_pos, $dx, $dy, $dz);
         }
      }
   }

   @chnkposes
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

sub world_is_solid_box { $_[0]->[2] && $_[0]->[0] ne ' ' }

sub _box_height_at {
   my ($pos, $radius) = @_;
   my $fpos = vfloor ($pos);
   my $box = world_get_box_at ($pos);
   #warn "BOX AT " . vstr ($fpos) . " [$box->[0]]\n";

   if ($box->[0] eq '/') { # slopes! # FIXME: direction of slope!
      my ($xrel) = $pos->[0] - $fpos->[0];

      my $a = 1 / (1 - ($radius - 0.001));
      my $yd = $xrel >= (1 - $radius) ? 1 : $a * $xrel;
      return $fpos->[1] + $yd

   } elsif ($box->[0] eq 'X') { # normal blocks
      return $fpos->[1] + 1;

   } else {
      return undef;
   }
}

sub _quadrant_offsets_at {
   my ($pos) = @_;

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

   map { my $z = $_; map { [$_, $z] } @xr } @zr
}

sub world_collide_cylinder_aabb {
   my ($pos, $height, $radius, $rcollide_normal) = @_;

   my ($recursion, $original_pos);
   $original_pos = [@$pos];

   RECOLLIDE:
   $recursion++;

   # we collide too much:
   if ($recursion > 6) {
      warn "collision occured on too many things. we couldn't backoff!";
      return ($original_pos); # found position is as good as any...
   }
   warn "collide at " . vstr ($pos) . " ($height, $radius)\n";

   # the "current" block
   my $head_pos = vaddd ($pos, 0, $height, 0);
   my $head_box = vfloor ($head_pos);

   # first check if we jumped against something above us:
   my $hbox = world_get_box_at ($head_box);
   if (world_is_solid_box ($hbox)) {
      $$rcollide_normal = vaccum ($$rcollide_normal, [0, -1, 0]);
      $pos = vaddd ($pos, 0, -(($head_pos->[1] - $head_box->[1]) + 0.001), 0);
      warn "HEAD COLLISION!\n";
      goto RECOLLIDE;
   }

   my @quadrants = _quadrant_offsets_at ($pos);

   my $foot_box = vfloor ($pos);

   my @heights;
   my ($x, $z) = ($pos->[0], $pos->[2]);
   warn "POS $x $foot_box->[1] $z\n";
   for my $y ($foot_box->[1] - 1, $foot_box->[1]) {
      push @heights, map {
         my $h =
            _box_height_at ([$x + $_->[0] * $radius, $y, $z + $_->[1] * $radius], $radius);
         warn "HEIGHT @$_: $h => " .($pos->[1] - $h)."\n" if defined $h;
         $h
      } @quadrants;
   }
   # next: find max diffs, if max diff is above some limit collide
   # with the boxes sideways, otherwise continue by pushing the player
   # away from the side-walls and recurse to adjust his height
   for (@heights) {
      next unless defined $_;
      my $diff = $pos->[1] - $_;
      #TODO FIXME: continue diffing here, with negative coordinates!
      if ($diff < $radius) {
         warn "OCLLIDED DIFF: $diff\n";
         $$rcollide_normal = vaccum ($$rcollide_normal, [0, 1, 0]);
         $pos = vaddd ($pos, 0, ($radius - $diff) + 0.001, 0);
         goto RECOLLIDE;
      }
   }
   warn "No collision with " . vstr ($pos) . "\n";

   return $pos;

   #redef# my $fbox       = world_get_box_at ($foot_box);
   #redef# my $below_fbox = world_get_box_at (vsubd ($foot_box, 0, -1, 0));

   #redef# if ($fbox->[2] && $fbox->[0] eq '/') {
 # #redef#     my $box_y = $foot_box->[1] + 1;
   #redef#    my ($xrel) = $pos->[0] - $foot_box->[0];
   #redef#    my $a = 1 / (1 - ($radius - 0.001));
   #redef#    my $yd = $xrel >= (1 - $radius) ? 1 : $a * $xrel;
   #redef#    if ($yd > 0) {
   #redef#       my $box_y = ($foot_box->[1] + $yd) + 0.01;
   #redef#       warn "X SLOPE $yd $a $xrel [$box_y] ($box_y <=> $pos->[1])\n";
   #redef#       my $up_move = $box_y - $pos->[1];
   #redef#       if ($up_move > 0) {
   #redef#          $$rcollide_normal = vaccum ($$rcollide_normal, [0, 1, 0]);
   #redef#          my $new_pos = vaddd ($pos, 0, $up_move, 0);
   #redef#          warn "POS " . vstr ($pos) . " =slope> " . vstr ($new_pos) . "\n";

   #redef#          return world_collide_cylinder_aabb (
   #redef#             $new_pos, $height, $radius, $rcollide_normal, $recursion + 1, $original_pos);
   #redef#       }
   #redef#    }

   #redef# } elsif (world_is_solid_box ($fbox)) {
   #redef#    my $box_y = $foot_box->[1] + 1 + $radius;

   #redef#    $$rcollide_normal = vaccum ($$rcollide_normal, [0, 1, 0]);
   #redef#    my $new_pos = vaddd ($pos, 0, ($box_y - $pos->[1]) + 0.001, 0);
   #redef#    return world_collide_cylinder_aabb (
   #redef#       $new_pos, $height, $radius, $rcollide_normal, $recursion + 1, $original_pos);

   #redef# } elsif (world_is_solid_box ($below_fbox)) { # box is non-solid
   #redef#    my $box_y = $foot_box->[1] + $radius;
   #redef#    warn "BLWO\n";
   #redef#    if ($pos->[1] < $box_y) {
   #redef#       $$rcollide_normal = vaccum ($$rcollide_normal, [0, 1, 0]);
   #redef#       my $new_pos = vaddd ($pos, 0, ($box_y - $pos->[1]) + 0.001, 0);
   #redef#       return world_collide_cylinder_aabb (
   #redef#          $new_pos, $height, $radius, $rcollide_normal, $recursion + 1, $original_pos);
   #redef#    }
   #redef# }

   #redef# # now check if we collide in the X and Z plane with any of the boxes
   #redef# my $pos_2d = [$pos->[0], $pos->[2]];
   #redef# #warn "no head or food collision, checking " . vstr ($pos_2d) . "\n";

   #redef# for my $y ($foot_box->[1]..$head_box->[1]) {
   #redef#    for my $dx (@$xr) {
   #redef#       for my $dz (@$zr) {
   #redef#          my ($x, $z) = ($foot_box->[0] + $dx, $foot_box->[2] + $dz);
   #redef#          my $sbox = world_get_box_at ([$x, $y, $z]);

   #redef#          if ($y == $foot_box->[1] && $sbox->[0] eq '/') {
   #redef#             next; # skip slope boxes on the feet, they just move upward!

   #redef#          } elsif (world_is_solid_box ($sbox)) {
   #redef#             my $aabb_pt = _closest_pt_point_aabb_2d (
   #redef#                $pos_2d, [$x, $z], [$x + 1, $z + 1]);

   #redef#             my $dvec = vsub_2d ($pos_2d, $aabb_pt);
   #redef#             my $dvecl = vlength_2d ($dvec);
   #redef#             #d# warn "coll point $x $y $z: "
   #redef#             #d#      . vstr ($aabb_pt) . " pl "
   #redef#             #d#      . vstr ($pos_2d) . " dv "
   #redef#             #d#      . vstr ($dvec) . " ($dvecl)\n";

   #redef#             if ($dvecl == 0) {
   #redef#                $$rcollide_normal = [0, 1, 0];
   #redef#                #d# warn "collision happened INSIDE something!\n";
   #redef#                my $new_pos = vaddd ($pos, 0, 1, 0);
   #redef#                return world_collide_cylinder_aabb (
   #redef#                   $new_pos, $height, $radius, $rcollide_normal,
   #redef#                   $recursion + 1, $original_pos);
   #redef#             }

   #redef#             if ($dvecl < $radius) {
   #redef#                my $backoff_dist = ($radius - $dvecl) + 0.0001;

   #redef#                my $vn = vnorm ([$dvec->[0], 0, $dvec->[1]]);
   #redef#                #d# warn "backoff: $backoff_dist into " . vstr ($vn) . "\n";
   #redef#                $$rcollide_normal = vaccum ($$rcollide_normal, $vn);
   #redef#                my $new_pos = vadd ($pos, vsmul ($vn, $backoff_dist));
   #redef#                return world_collide_cylinder_aabb (
   #redef#                   $new_pos, $height, $radius, $rcollide_normal,
   #redef#                   $recursion + 1, $original_pos);
   #redef#             }
   #redef#          }
   #redef#       }
   #redef#    }
   #redef# }

   #redef# return $pos;
}

# collide sphere at $pos with radius $rad
#   0.00059 secsPcoll in flight without collisions
#   0.00171secsPcoll to 0.00154secsPcoll when colliding with floor
# after own vector math module:
#   0.00032 secsPcoll in flight
#   0.00068 secsPcoll on floor  # i find this amazing!
sub world_collide {
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
               my $bx = world_get_box_at ($cur_box);
               next unless $bx->[2] && $bx->[0] ne ' ';

               my ($col_dir, $pos_adj) = _collide_sphere_box ($spos, $srad, $cur_box);
               if ($col_dir) { # collided!
                  if (defined $$rcoll && defined $pos_adj) {
                     $$rcoll += $col_dir;
                  } else {
                     $$rcoll = $col_dir;
                  }

                  if (defined $pos_adj) { # was able to move to safer location?
                     return world_collide (
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

