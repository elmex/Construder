package Games::Blockminer::Client::MapChunk;
use common::sense;
use Math::VectorReal;

=head1 NAME

Games::Blockminer::Client::MapChunk - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

A chunk of the Blockminer world.

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer::Client::MapChunk->new (%args)

=cut

our ($SIZE) = 35;

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   return $self
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
      _map_get_if_exists ($map, $x, $y,     $z + 1),
      _map_get_if_exists ($map, $x, $y,     $z - 1),
   );
   @n
 #  my ($cur, $top, $bot, $left, $right, $front, $back) 
}

sub random_fill {
   my ($self) = @_;

   my @types = ('X', ' ');
   my $map = [];
   my @lights;

   for (my $x = 0; $x < $SIZE; $x++) {
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $z = 0; $z < $SIZE; $z++) {
            my $t = 'X';
            if (int (rand ($SIZE * $SIZE * $SIZE)) <= 100) {
               warn "PUTHOLE $x $y $z\n";
               $t = ' ';
            } elsif (int (rand ($SIZE * $SIZE * $SIZE)) <= 3) {
               warn "PUTLIGHT $x $y $z\n";
               push @lights, [$x, $y, $z];
            }
            $map->[$x]->[$y]->[$z] = [$t, 0, 1];
         }
      }
   }

   # erode:
   my $last_blk_cnt = 0;
   for (1..4) {
      my $new_map = [];
      my $blk_cnt = 0;
      for (my $x = 0; $x < $SIZE; $x++) {
         for (my $y = 0; $y < $SIZE; $y++) {
            for (my $z = 0; $z < $SIZE; $z++) {
               my ($cur, $top, $bot, $left, $right, $front, $back)
                  = _neighbours ($map, $x, $y, $z);

               my $n = [@$cur];

               my $cnt = 0;
               $cnt++ if $top->[0]   eq ' ';
               $cnt++ if $bot->[0]   eq ' ';
               $cnt++ if $left->[0]  eq ' ';
               $cnt++ if $right->[0] eq ' ';
               $cnt++ if $front->[0] eq ' ';
               $cnt++ if $back->[0]  eq ' ';

               $n->[0] = ' ' if $cnt >= 1;

               $blk_cnt++ if $n->[0] ne ' ';

               $new_map->[$x]->[$y]->[$z] = $n;
            }
         }
      }
      $map = $new_map;
      warn "erode $_: $blk_cnt blocks (last $last_blk_cnt)\n";
      last if $last_blk_cnt == $blk_cnt;
      $last_blk_cnt = $blk_cnt;
      $blk_cnt = 0;
   }


   for (my $x = 0; $x < $SIZE; $x++) {
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $z = 0; $z < $SIZE; $z++) {
            my ($cur, $top, $bot, $left, $right, $front, $back)
               = _neighbours ($map, $x, $y, $z);
            my $cnt = 0;
            $cnt++ if $top->[0]   eq ' ';
            $cnt++ if $bot->[0]   eq ' ';
            $cnt++ if $left->[0]  eq ' ';
            $cnt++ if $right->[0] eq ' ';
            $cnt++ if $front->[0] eq ' ';
            $cnt++ if $back->[0]  eq ' ';

            if ($cnt == 0
                && not (
                   $x == 0 || $x == $SIZE - 1
                   || $y == 0 || $y == $SIZE - 1
                   || $z == 0 || $z == $SIZE - 1)
            ) {
               $cur->[2] = 0;
            } else {
               $cur->[2] = 1;
            }
         }
      }
   }

   for (@lights) {
      my ($x, $y, $z) = @$_;
      warn "LIGHT $x, $y, $z\n";
      my $DIST = 20;
      for (my $xi = -$DIST; $xi <= $DIST; $xi++) {
         for (my $yi = -$DIST; $yi <= $DIST; $yi++) {
            for (my $zi = -$DIST; $zi <= $DIST; $zi++) {
               my $dist = (abs ($xi) + abs ($yi) + abs ($zi)) / 3;
               next if $dist > 6.6;
               my ($tile) = _map_get_if_exists ($map, $x + $xi, $y + $yi, $z + $zi);
               # TODO: fix light :)
               my $level = (($dist ** 2) * (-20 / 6.6 ** 2)) + 20;
               $tile->[1] = $level if $tile->[1] < $level;
            }
         }
      }
   }

   for (my $x = 0; $x < $SIZE; $x++) {
      my $plane_light;
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $z = 0; $z < $SIZE; $z++) {
            my ($tile) = _map_get_if_exists ($map, $x, $y, $z);
            #$plane_light .= sprintf "%-4.1f ", $tile->[1];
            $plane_light .= "$tile->[0]|$tile->[2] ";
 #           $tile->[1] = int $tile->[1];
         }
         $plane_light .= "\n";
      }
      warn "plane $x:\n$plane_light\n";
   }
   $self->{map} = $map;
}

sub _map_get_if_exists {
   my ($map, $x, $y, $z) = @_;
   return ["X", 0] if $x < 0     || $y < 0     || $z < 0;
   return ["X", 0] if $x >= $SIZE || $y >= $SIZE || $z >= $SIZE;
   $map->[$x]->[$y]->[$z]
}

sub _closest_pt_point_aabb {
   my ($pt, $box_min, $box_max) = @_;
   my @pt  = $pt->array;
   my @box_min = $box_min->array;
   my @box_max = $box_max->array;
   my @out;
   for (0..2) {
      my $pv = $pt[$_];
      $pv = $box_min[$_] if $pv < $box_min[$_];
      $pv = $box_max[$_] if $pv > $box_max[$_];
      push @out, $pv;
   }
   vector (@out)
}

#sub _sqdist_pt_aabb {
#   my ($pt, $box_min, $box_max) = @_;
#   my @pt  = $pt->array;
#   my @box_min = $box_min->array;
#   my @box_max = $box_max->array;
#   my $dist;
#   for (0..2) {
#      my $pv = $pt[$_];
#      $pv = if $pv < $box_min[$_];
#      $pv = if $pv > $box_max[$_];
#      push @out, $pv;
#   }
#   vector (@out)
#}

sub _collide_box {
   my ($box, $pos) = @_;
   my $max = $box + vector (1, 1, 1);
   my $abpt = _closest_pt_point_aabb ($pos, $box, $max);
   my $dv = $pos - $abpt;
   return ($dv, $abpt)
}

sub _is_solid_box {
   my ($map, $box) = @_;
   my $b = _map_get_if_exists ($map, $box->array);
   $b->[2] && $b->[0] ne ' '
}

# collide sphere at $pos with radius $rad
sub collide {
   my ($self, $pos, $rad, $rcoll, $rec) = @_;
   my $orig_pos = $pos;
   $pos = -vector ($pos->x - $SIZE * int ($pos->x / $SIZE),
                   $pos->y - $SIZE * int ($pos->y / $SIZE),
                   $pos->z - $SIZE * int ($pos->z / $SIZE));
   #d# warn "player global $orig_pos, local $pos\n";

   if ($rec > 5) {
      return ($orig_pos);
   }

   # find the 6 adjacent blocks
   # and check:
   #   bottom of top
   #   top of bottom
   #   and the interiors of the 4 adjacent blocks


   my $map = $self->{map};
#   my ($cur, $top, $bot, $left, $right, $front, $back)
#      = _neighbours ($map, $pos->array);

   # the "current" block
   my $my_box = vector (int $pos->x, int $pos->y, int $pos->z);

   for my $x (-1..1) {
      for my $y (-1..1) {
         for my $z (-1..1) {
            my $cur_box = $my_box + vector ($x, $y, $z);
            next unless _is_solid_box ($map, $cur_box);
            my ($dv, $ipt) = _collide_box ($cur_box, $pos);
            #d#warn "solid box at $cur_box, dist vec $dv |"
            #d#     . (sprintf "%9.4f", $dv->length)
            #d#     . "|, coll point $ipt\n";
            if ($dv->length == 0) { # ouch, directly in the side?
               $dv = vector (0, 0.1, 0); # shoot him up :->
            }
            if ($dv->length < $rad) {
               my $back_dist = ($rad - $dv->length) + 0.00001;
               my $new_pos = $orig_pos - ($dv->norm * $back_dist);
               $$rcoll = 1;
               return $self->collide ($new_pos, $rad, $rcoll, $rec + 1);
            }
         }
      }
   }

   return ($orig_pos);
#   my $block_pos = vector (int $pos->x, int $pos->y, int $pos->z);
#
#   my $map = $self->{map};
#   my ($cur, $top, $bot, $left, $right, $front, $back)
#      = _neighbours ($map, $pos->array);
#
# #  warn "check collision $pos $rad\n";
#   if ($bot->[2] && $bot->[0] eq 'X') {
#      my ($n, $d) = plane (
#         $block_pos, $block_pos + vector (1, 0, 1), $block_pos + vector (1, 0, 0)
#      );
#      my $dist = ($pos - $block_pos) . $n;
#      warn "DIST FROM PLANE $dist $rad\n";
#      if ($dist < $rad) {
#         return vector (0, -1, 0) * ($rad - $dist);
#      }
#      warn "POS COLLIDE $dist | $pos | $n\n";
#   }
#   my $map = $self->{map};
#   for (my $x = 0; $x < $SIZE; $x++) {
#      for (my $y = 0; $y < $SIZE; $y++) {
#         for (my $z = 0; $z < $SIZE; $z++) {
#            my $blok = $map->[$x]->[$y]->[$z];
#            if ($blok->[0] eq 'X') {
#               warn "CHECK $x $y $z..\n";
#               my $d = _collide_quad (vector ($x, $y, $z), $pos, $rad);
#               warn "COLLIDE $d\n";
# #              return $d if $d;
#            }
#         }
#      }
#   }

   undef
}

sub update_visibility {
   my ($self) = @_;
   # find out which blocks are possibly visible by defining
   # the outer "hull" of the chunk.
   #
   # TODO: find out how to do this iteratively if new chunks
   #       are "joining"
   #       Just reevaluate this, taking into account the adjacent chunks.

#   my $map = $self->{map};

#   for (my $x = 0; $x < $SIZE; $x++) {
#      for (my $y = 0; $y < $SIZE; $y++) {
#         for (my $z = 0; $z < $SIZE; $z++) {
#            my ($tile) = _map_get_if_exists ($map, $x, $y, $z);
#         }
#      }
#   }

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

