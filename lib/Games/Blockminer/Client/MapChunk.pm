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

sub random_fill {
   my ($self) = @_;

   my @types = ('X', ' ');
   my $map = [];
   my @lights;

   for (my $x = 0; $x < $SIZE; $x++) {
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $z = 0; $z < $SIZE; $z++) {
            my $t = 'X';
            if (int (rand ($SIZE * $SIZE * $SIZE)) <= 1) {
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
   for (1..10) {
      my $new_map = [];
      my $invis_blk = 0;
      my $blk_cnt = 0;
      for (my $x = 0; $x < $SIZE; $x++) {
         for (my $y = 0; $y < $SIZE; $y++) {
            for (my $z = 0; $z < $SIZE; $z++) {
               my ($cur, $top, $bot, $left, $right, $front, $back) = (
                  _map_get_if_exists ($map, $x, $y,     $z),
                  _map_get_if_exists ($map, $x, $y + 1, $z),
                  _map_get_if_exists ($map, $x, $y - 1, $z),
                  _map_get_if_exists ($map, $x - 1, $y, $z),
                  _map_get_if_exists ($map, $x + 1, $y, $z),
                  _map_get_if_exists ($map, $x, $y,     $z + 1),
                  _map_get_if_exists ($map, $x, $y,     $z - 1),
               );

               my $n = [@$cur];

               my $cnt = 0;
               $cnt++ if $top->[0]   eq ' ';
               $cnt++ if $bot->[0]   eq ' ';
               $cnt++ if $left->[0]  eq ' ';
               $cnt++ if $right->[0] eq ' ';
               $cnt++ if $front->[0] eq ' ';
               $cnt++ if $back->[0]  eq ' ';

               $n->[0] = ' ' if $cnt >= 1;

               if ($cnt == 0
                   && not (
                      $x == 0 || $x == $SIZE - 1
                      || $y == 0 || $y == $SIZE - 1
                      || $z == 0 || $z == $SIZE - 1)
               ) {
                  $n->[2] = 0;
                  # FIXME: need to checkout why this fails with so few seeds
                  $invis_blk++;
               } else {
                  $n->[2] = 1;
               }
               #d#warn "$x $y $z: $cnt\n";

               $blk_cnt++ if $n->[0] ne ' ';

               $new_map->[$x]->[$y]->[$z] = $n;
            }
         }
      }
      $map = $new_map;
      warn "erode $_: $blk_cnt blocks (last $last_blk_cnt, inv $invis_blk)\n";
      last if $last_blk_cnt == $blk_cnt;
      $last_blk_cnt = $blk_cnt;
      $blk_cnt = 0;
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

   #d# for (my $x = 0; $x < $SIZE; $x++) {
   #d#    my $plane_light;
   #d#    for (my $y = 0; $y < $SIZE; $y++) {
   #d#       for (my $z = 0; $z < $SIZE; $z++) {
   #d#          my ($tile) = _map_get_if_exists ($map, $x, $y, $z);
   #d#          $plane_light .= sprintf "%-4.1f ", $tile->[1];
   #d#          $tile->[1] = int $tile->[1];
   #d#       }
   #d#       $plane_light .= "\n";
   #d#    }
   #d#    warn "plane $x:\n$plane_light\n";
   #d# }
   $self->{map} = $map;
}

sub _map_get_if_exists {
   my ($map, $x, $y, $z) = @_;
   return ["X", 0] if $x < 0     || $y < 0     || $z < 0;
   return ["X", 0] if $x >= $SIZE || $y >= $SIZE || $z >= $SIZE;
   $map->[$x]->[$y]->[$z]
}

sub _collide_quad {
   my ($base, $pos, $rad) = @_;

   my ($norm, $d) = plane ($base, $base + vector (0, 0, 1), $base + vector (1, 0, 1));
   my $distance = $norm . $pos;
   if ($distance <= $rad) {
      return $norm * ($rad - $distance);
   }
}

# collide sphere at $pos with radius $rad
sub collide {
   my ($self, $pos, $rad) = @_;
   $pos = vector ($pos->x - int ($pos->x / $SIZE),
                  $pos->y - int ($pos->y / $SIZE),
                  $pos->z - int ($pos->z / $SIZE));

   # find the 6 adjacent blocks
   # and check:
   #   bottom of top
   #   top of bottom
   #   and the interiors of the 4 adjacent blocks

   warn "POS COLLIDE $pos\n";
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

