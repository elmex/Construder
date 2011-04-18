package Games::Blockminer::Client::MapChunk;
use common::sense;

=head1 NAME

Games::Blockminer::Client::MapChunk - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

A chunk of the Blockminer world.

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer::Client::MapChunk->new (%args)

=cut

our ($SIZE) = 25;

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
            if (int (rand ($SIZE)) == $SIZE - 1) {
               $t = ' ';
            } elsif (int (rand ($SIZE)) == $SIZE - 1) {
               push @lights, [$x, $y, $z];
            }
            $map->[$x]->[$y]->[$z] = [$t, 0];
         }
      }
   }

   # erode:
   my $last_blk_cnt = 0;
   for (1..10) {
      my $new_map = [];
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

               $n->[0] = ' ' if $cnt >= 2;
               #d#warn "$x $y $z: $cnt\n";

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

   for (@lights) {
      my ($x, $y, $z) = @$_;
      warn "LIGHT $x, $y, $z\n";
      for (my $xi = -10; $xi <= 10; $xi++) {
         for (my $yi = -10; $yi <= 10; $yi++) {
            for (my $zi = -10; $zi <= 10; $zi++) {
               my ($tile) = _map_get_if_exists ($map, $x + $xi, $y + $yi, $z + $zi);
               # TODO: fix light :)
               my $dist = (abs ($xi) * abs ($yi) * abs ($zi)) ** (1/3);
               my $level = (10 - $dist) * 2;

               $tile->[1] = $level;
            }
         }
      }
   }

   $self->{map} = $map;
}

sub _map_get_if_exists {
   my ($map, $x, $y, $z) = @_;
   return ["X", 0] if $x < 0     || $y < 0     || $z < 0;
   return ["X", 0] if $x >= $SIZE || $y >= $SIZE || $z >= $SIZE;
   $map->[$x]->[$y]->[$z]
}

sub update_visibility {
   # find out which blocks are possibly visible by defining
   # the outer "hull" of the chunk.
   #
   # TODO: find out how to do this iteratively if new chunks
   #       are "joining"
   #       Just reevaluate this, taking into account the adjacent chunks.
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

