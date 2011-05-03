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
   world_collide
   world_collide_cylinder_aabb
   world_is_solid_box
   world_intersect_ray_box
   world_get_box_at
   world_get_chunk world_get_chunk_at
   world_set_chunk
   world_change_chunk_at world_change_chunk
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

sub world_change_chunk {
   my ($pos) = @_;
   world ()->event (chunk_changed => $pos);
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
      # find the direction away from the center
      my $inside_dir = vsub ($sphere_pos, vadd ($box, 0.5, 0.5, 0.5));
      vinorm ($inside_dir);
      # and move out one radius!
      return ($inside_dir, vsmul ($inside_dir, $sphere_rad));

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

# collide sphere at $pos with radius $rad
#   0.00059 secsPcoll in flight without collisions
#   0.00171secsPcoll to 0.00154secsPcoll when colliding with floor
# after own vector math module:
#   0.00032 secsPcoll in flight
#   0.00068 secsPcoll on floor  # i find this amazing!
sub world_collide {
   my ($pos, $rad, $rcoll, $rec, $orig_pos) = @_;

   my ($rec, $orig_pos) = (0, [@$pos]);

   RECOLLIDE:
   $rec++;
   # we collide too much:
   if ($rec > 6) {
      warn "collision occured on too many things. we couldn't backoff!";
      return ($orig_pos); # found position is as good as any...
   }


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
      my ($spos, $srad, $coll_y) = @$sphere;
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
               next unless world_is_solid_box ($bx);

               my ($col_dir, $pos_adj) = _collide_sphere_box ($spos, $srad, $cur_box);
               if ($col_dir && vdot ([0, $coll_y, 0], $col_dir) <= 0) { # collided!
                  $$rcoll = vaccum ($$rcoll, $col_dir);

                  if (defined $pos_adj) { # was able to move to safer location?
                     $pos = vadd ($pos, $pos_adj);
                     goto RECOLLIDE;

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

