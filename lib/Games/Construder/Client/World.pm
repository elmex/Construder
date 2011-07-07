# Games::Construder - A 3D Game written in Perl with an infinite and modifiable world.
# Copyright (C) 2011  Robin Redeker
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
package Games::Construder::Client::World;
use common::sense;
use Games::Construder::Vector;
use Games::Construder;
use POSIX qw/floor/;
use Object::Event;

require Exporter;
use POSIX qw/floor/;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   world_pos2chunk
   world_visible_chunks_at
   world_collide
   world_collide_cylinder_aabb
   world_is_solid_box
   world_intersect_ray_box
   world_get_box_at
   world_get_chunk world_get_chunk_at
   world_set_chunk
   world_delete_chunk
   world_change_chunk_at world_change_chunk
   world_pos2id
   world_id2pos
   world_find_free_spot
   world_init
   world
/;

=head1 NAME

Games::Construder::Client::World - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

our $CHNK_SIZE = 12;
our $BSPHERE   = sqrt (3 * (($CHNK_SIZE/2) ** 2));
my @CHUNKS;

sub world_init {
}

sub world_pos2chunk {
   @{vfloor (vsdiv ($_[0], $CHNK_SIZE))};
}

sub world_pos2id {
   my ($pos) = @_;
   join "x", map { $_ < 0 ? "N" . abs ($_) : $_ } @{vfloor ($pos)};
}

sub world_id2pos {
   my ($id) = @_;
   [map { s/^N/-/; $_ } split /x/, $id]
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

sub _collide_sphere_box {
   my ($sphere_pos, $sphere_rad, $box) = @_;

   my $abpt =
      Games::Construder::Math::point_aabb_distance (
         @$sphere_pos, @$box, @{vaddd ($box, 1, 1, 1)});
   my $dv   = vsub ($sphere_pos, $abpt);

   #d#warn "solid box at $cur_box, dist vec $dv |"
   #d#     . (sprintf "%9.4f", $dv->length) . "\n";

   my $dvlen = vlength ($dv);

   if ($dvlen == 0) { # ouch, directly in the side?
      # find the direction away from the center
      my $inside_dir = vsub ($sphere_pos, vadd ($box, 0.5, 0.5, 0.5));
      if (vlength ($inside_dir) > 0.0001) {
         vinorm ($inside_dir);
      } else { # he IS in the center
         $inside_dir = [0, 1, 0]; # move up :)
      }
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

sub world_is_solid_box { $_[0]->[2] && $_[0]->[0] != 0 }

sub world_adjacent_walls {
   my ($pos, $rad) = @_;

   my %poses;
   for my $dx (-$rad, $rad) {
      for my $dz (-$rad, $rad) {
         my $p = vfloor (vaddd ($pos, $dx, 0, $dz));
         $poses{world_pos2id ($p)} = $p;
      }
   }

   values %poses
}

# collide sphere at $pos with radius $rad
#   0.00059 secsPcoll in flight without collisions
#   0.00171secsPcoll to 0.00154secsPcoll when colliding with floor
# after own vector math module:
#   0.00032 secsPcoll in flight
#   0.00068 secsPcoll on floor  # i find this amazing!
sub world_collide {
   my ($pos, $rad, $plh, $rcoll) = @_;

   my ($rec, $orig_pos) = (0, [@$pos]);

   RECOLLIDE:
   $rec++;
   # we collide too much:
   if ($rec > 8) {
      #d# warn "collision occured on too many things. we couldn't backoff!";
      my $np = world_find_free_spot ($orig_pos, 0);
      $$rcoll = 1;
      $np = $orig_pos unless $np;
      $np = vaddd ($np, $rad + 0.01, $rad + 0.01, $rad + 0.01);
      return $np;
   }

   my @wall_boxes = world_adjacent_walls ($pos, $rad);
   my @wboxes;
   for (@wall_boxes) {
      my $b = vfloor (vaddd ($_, 0, $plh, 0));
      push @wboxes, $_, $b;
   }

   for my $cur_box (@wboxes) {
      next unless Games::Construder::World::is_solid_at (@$cur_box);
      $cur_box->[1] = 0;
      my ($col_dir, $pos_adj) =
         _collide_sphere_box ([$pos->[0], 0, $pos->[2]], $rad, $cur_box);

      if ($col_dir) { # collided!
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

   for my $sphere_y (0, $plh) {
      my ($spos, $srad, $coll_y) =
         (vaddd ($pos, 0, $sphere_y, 0), $rad, $sphere_y > 0 ? -1 : 1);

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
               next unless Games::Construder::World::is_solid_at (@$cur_box);

               my ($col_dir, $pos_adj) = _collide_sphere_box ($spos, $srad, $cur_box);
               if ($col_dir) { # collided!
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

sub world_find_free_spot {
   my ($pos, $wflo) = @_;
   $wflo = 0 unless defined $wflo;
   Games::Construder::World::find_free_spot (@$pos, $wflo);
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License.

=cut

1;

