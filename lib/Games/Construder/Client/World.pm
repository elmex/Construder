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
   world_intersect_ray_box
   world_get_box_at
   world_get_chunk world_get_chunk_at
   world_set_chunk
   world_delete_chunk
   world_change_chunk_at world_change_chunk
   world_pos2id
   world_id2pos
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
   my ($sphere_pos, $sphere_rad, $box, $box_h) = @_;

   my $abpt =
      Games::Construder::Math::point_aabb_distance (
         @$sphere_pos, @$box, @{vaddd ($box, 1, $box_h, 1)});
   my $dv = vsub ($sphere_pos, $abpt);

   warn "solid box at @$box, dist vec @$dv |"
        . (sprintf "%9.4f", vlength ($dv)) . "\n";

   my $dvlen = vlength ($dv);

   if ($dvlen == 0) { # ouch, directly in the side?
      # find the direction away from the center
      my $inside_dir = vsub ($sphere_pos, vadd ($box, 0.5, $box_h / 2, 0.5));
      if (vlength ($inside_dir) > 0.0001) {
         vinorm ($inside_dir);
      } else { # he IS in the center
         $inside_dir = [0, $box_h, 0]; # move up :)
      }
      warn "WHUT\n";
      # and move out one radius!
      return ($inside_dir, vsmul ($inside_dir, $sphere_rad));

      warn "player landed directly on the surface\n";
      return ([0, 0, 0]);
   }

   if ($dvlen < $sphere_rad) {
      my $back_dist = ($sphere_rad - $dvlen) + 0.00001;
      warn "BACKDIST $back_dist\n";
      return ($dv, vsmul (vnorm ($dv, $dvlen), $back_dist));
   }

   return ()
}

# collide sphere at $pos with radius $rad
#   0.00059 secsPcoll in flight without collisions
#   0.00171secsPcoll to 0.00154secsPcoll when colliding with floor
# after own vector math module:
#   0.00032 secsPcoll in flight
#   0.00068 secsPcoll on floor  # i find this amazing!
sub world_collide {
   my ($pos, $rad, $rcoll) = @_;

   my ($rec, $orig_pos) = (0, [@$pos]);

   RECOLLIDE:
   $rec++;
   # we collide too much:
   if ($rec > 20) {
      #d# warn "collision occured on too many things. we couldn't backoff!";
      return ($orig_pos); # found position is as good as any...
   }

   my $my_box = vfloor ($pos);

   my (%boxes) = ();
   $boxes{world_pos2id ($my_box)} = $my_box;
   my $mrad = $rad + 0.01;
   for my $dx (-$mrad, $mrad) {
      for my $dy (-2, -1, 1, 2) {
         for my $dz (-$mrad, $mrad) {
            my $bx = vfloor (vaddd ($pos, $dx, $dy, $dz));
            $boxes{world_pos2id ($bx)} = $bx;
         }
      }
   }
   warn "COLLIDE @$pos ".join (", ", sort keys %boxes)."\n";

   for my $cur_box (values %boxes) {
      next unless Games::Construder::World::is_solid_at (@$cur_box);

      my $sc_box = [@$cur_box];
      $sc_box->[1] *= 0.25;
      my $s_pos  = [@$pos];
      $s_pos->[1] *= 0.25;

      my ($col_dir, $pos_adj) = _collide_sphere_box ($s_pos, $rad, $sc_box, 0.25);
      if ($col_dir) {
         $$rcoll = vaccum ($$rcoll, $col_dir);

         if (defined $pos_adj) { # was able to move to safer location?
            warn "ADJUSTING1 @$pos_adj | @$s_pos\n";
            $pos = vadd ($s_pos, $pos_adj);
            $pos->[1] *= 4;
            warn "ADJUSTING2 @$pos_adj | @$pos\n";
            goto RECOLLIDE;

         } else { # collided with something, but unable to move to safe location
            warn "player collided with something, but we couldn't repell him!";
            return ($orig_pos);
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

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

