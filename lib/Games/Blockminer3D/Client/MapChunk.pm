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
   return [" ", 20, 1] if $x < 0     || $y < 0     || $z < 0;
   return [" ", 20, 1] if $x >= $SIZE || $y >= $SIZE || $z >= $SIZE;
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

sub cube_fill {
   my ($self) = @_;

   my $map = [];
   for (my $x = 0; $x < $SIZE; $x++) {
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $z = 0; $z < $SIZE; $z++) {
            my $t = 'X';
            if ($x == 0 || $y == 0 || $z == 0
                || ($z == ($SIZE - 1))
                || ($x == ($SIZE - 1))
                || ($y == ($SIZE - 1))
            ) {
               $map->[$x]->[$y]->[$z] = ['X', 20, 1];
            } else {
               $map->[$x]->[$y]->[$z] = [' ', 20, 1];
            }
         }
      }
   }
   $self->{map} = $map;
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
            if (int (rand ($SIZE * $SIZE * $SIZE)) <= 60) {
               warn "PUTHOLE $x $y $z\n";
               $t = ' ';
            } elsif (int (rand ($SIZE * $SIZE * $SIZE)) <= 1) {
               warn "PUTLIGHT $x $y $z\n";
               push @lights, [$x, $y, $z];
            }
            #                        content, light, visibility
            $map->[$x]->[$y]->[$z] = [$t, 0, 1];
         }
      }
   }

   # erode:
   my $last_blk_cnt = 0;
   for (1..3) {
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


   my $visible;
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
               $visible++;
            }
         }
      }
   }
   warn "visible blocks $visible\n";

   for (@lights) {
      my ($x, $y, $z) = @$_;
      warn "LIGHT $x, $y, $z\n";
      my $DIST = 5;
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
            if ($cur->[0] eq 'X') {
               my @faces;

               if ($front->[2] && $front->[0] ne 'X') {
                  push @faces, 0
               }
               if ($top->[2] && $top->[0] ne 'X') {
                  push @faces, 1
               }
               if ($back->[2] && $back->[0] ne 'X') {
                  push @faces, 2
               }
               if ($left->[2] && $left->[0] ne 'X') {
                  push @faces, 3
               }
               if ($right->[2] && $right->[0] ne 'X') {
                  push @faces, 4
               }
               if ($bot->[2] && $bot->[0] ne 'X') {
                  push @faces, 5
               }

               push @quads, [
                  [$x, $y, $z],
                  \@faces,
                  $cur->[1],
 #                 $cur->[0] eq 'X' ? "filth.x11.32x32" : ""
                  $cur->[0] eq 'X' ? "metal05" : ""
               ];
            }
         }
      }
   }
   $self->{quads_cache} = \@quads;
   @quads
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

