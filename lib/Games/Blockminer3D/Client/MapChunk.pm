package Games::Blockminer3D::Client::MapChunk;
use common::sense;
use Time::HiRes qw/time/;
use OpenGL qw/:all/;
use Games::Blockminer3D::Vector;

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

our $SIZE = 12;
our $BSPHERE = sqrt (3 * (($SIZE/2) ** 2));

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
   return [0, 16, 1] if $x < 0     || $y < 0     || $z < 0;
   return [0, 16, 1] if $x >= $SIZE || $y >= $SIZE || $z >= $SIZE;
   #$map->[$x + ($y + $z * $SIZE) * $SIZE]
   $map->[$x]->[$y]->[$z]# + ($y + $z * $SIZE) * $SIZE]
}

sub _neighbours {
   my ($map, $x, $y, $z) = @_;
 #  my ($cur, $top, $bot, $left, $right, $front, $back) 
   (
      _map_get_if_exists ($map, $x, $y,     $z),
      _map_get_if_exists ($map, $x, $y + 1, $z),
      _map_get_if_exists ($map, $x, $y - 1, $z),
      _map_get_if_exists ($map, $x - 1, $y, $z),
      _map_get_if_exists ($map, $x + 1, $y, $z),
      _map_get_if_exists ($map, $x, $y,     $z - 1),
      _map_get_if_exists ($map, $x, $y,     $z + 1),
   )
}

sub _data2array {
   my ($dat) = @_;
   my ($blk, $meta, $add) = unpack "nCC", $dat;
   my ($type, $light) = (($blk & 0xFFF0) >> 4, ($blk & 0x000F));
   [$type, $light, $meta, $add]
}

sub data_fill {
   my ($self, $data) = @_;

   my $t1 = time;
   my $map = [];
   for (my $z = 0; $z < $SIZE; $z++) {
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $x = 0; $x < $SIZE; $x++) {
            my $chnk_offs = $x + $y * $SIZE + $z * ($SIZE ** 2);
            my $c = $map->[$x]->[$y]->[$z] = _data2array (substr $data, $chnk_offs * 4, 4);
            $c->[2] = 1;

            #d#warn "DATAFILL: $x,$y,$z: " . JSON->new->encode ($map->[$x]->[$y]->[$z]) . "\n";
         }
      }
   }

   $self->{map} = $map;
   return;

   my $visible;
   for (my $z = 0; $z < $SIZE; $z++) {
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $x = 0; $x < $SIZE; $x++) {
            my ($cur, $top, $bot, $left, $right, $front, $back)
               = _neighbours ($map, $x, $y, $z);
            my $cnt = 0;
            $cnt++ if $top->[0]   == 0;
            $cnt++ if $bot->[0]   == 0;
            $cnt++ if $left->[0]  == 0;
            $cnt++ if $right->[0] == 0;
            $cnt++ if $front->[0] == 0;
            $cnt++ if $back->[0]  == 0;

            if ($cnt == 0
                && not (
                   $x == 0 || $x == $SIZE - 1
                   || $y == 0 || $y == $SIZE - 1
                   || $z == 0 || $z == $SIZE - 1)
            ) {
               $cur->[2] = 0;
 #              $map->[$x]->[$y]->[$z] = [1, 16, 1];
            } else {
               $cur->[2] = 1;
               $visible++;
            }
         }
      }
   }
   $self->visible_quads;

   warn "VISIBLE: $visible : ".(time - $t1)."\n";
   $self->{map} = $map;
}

my @indices  = (
   qw/ 0 1 2 3 /, # 0 front
   qw/ 1 5 6 2 /, # 1 top
   qw/ 7 6 5 4 /, # 2 back
   qw/ 4 5 1 0 /, # 3 left
   qw/ 3 2 6 7 /, # 4 right
   qw/ 3 7 4 0 /, # 5 bottom
);

#my @normals = (
#   [ 0, 0,-1],
#   [ 0, 1, 0],
#   [ 0, 0, 1],
#   [-1, 0, 0],
#   [ 1, 0, 0],
#   [ 0,-1, 0],
#),
my @vertices = (
   [ 0,  0,  0 ],
   [ 0,  1,  0 ],
   [ 1,  1,  0 ],
   [ 1,  0,  0 ],

   [ 0,  0,  1 ],
   [ 0,  1,  1 ],
   [ 1,  1,  1 ],
   [ 1,  0,  1 ],
);


sub visible_quads {
   my ($self, $res) = @_;

   my (@vertexes, @colors, @texcoords);

   my $map = $self->{map};

   my $quad_cnt;
   FACES:
   for (my $z = 0; $z < $SIZE; $z++) {
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $x = 0; $x < $SIZE; $x++) {
            my ($cur, $top, $bot, $left, $right, $front, $back)
               = _neighbours ($map, $x, $y, $z);
            next unless $cur->[2];
            if ($cur->[0] != 0) {
               my @faces;
               my ($txtid, $surf, $uv) = $res->obj2texture ($cur->[0]);

               if ($front->[2] && $front->[0] == 0) {
                  push @faces, [0, $front->[1] / 15]
               }
               if ($top->[2] && $top->[0] == 0) {
                  push @faces, [1, $top->[1] / 15]
               }
               if ($back->[2] && $back->[0] == 0) {
                  push @faces, [2, $back->[1] / 15]
               }
               if ($left->[2] && $left->[0] == 0) {
                  push @faces, [3, $left->[1] / 15]
               }
               if ($right->[2] && $right->[0] == 0) {
                  push @faces, [4, $right->[1] / 15];
               }
               if ($bot->[2] && $bot->[0] == 0) {
                  push @faces, [5, $bot->[1] / 15]
               }

               for (@faces) {
                  my ($faceidx, $color) = @$_;
                  $quad_cnt++;
                  push @vertexes, map {
                     my $v = $vertices[$indices[$faceidx * 4 + $_]];
                     (
                        $v->[0] + $x,
                        $v->[1] + $y,
                        $v->[2] + $z,
                     )
                  } 0..3;
                  push @colors, (
                     $color, $color, $color,
                     $color, $color, $color,
                     $color, $color, $color,
                     $color, $color, $color,
                  );
                  push @texcoords, (
                     $uv->[2], $uv->[3],
                     $uv->[2], $uv->[1],
                     $uv->[0], $uv->[1],
                     $uv->[0], $uv->[3],
 #                    1, 1,
 #                    1, 0,
 #                    0, 0,
 #                    0, 1
                  );
               }

              # my ($pos, $faces, $light, $tex) = @$_;
               #d# warn "QUAD: @faces at $x, $y, $z ($cur->[1])\n";
              # push @quads, [
              #    [$x, $y, $z], # pos
              #    \@faces,      # faces
              #    $cur->[0]     # object type id
              # ];
            }
         }
      }
   }
   warn "GOT: " . scalar (@vertexes) . " verts, " . scalar (@colors) . " colors and " . scalar (@texcoords) . " texcoords and $quad_cnt quads\n";
 #d#  warn "LIST[@vertexes | @colors | @texcoords]\n";

   [
      OpenGL::Array->new_list (GL_FLOAT, @vertexes),
      OpenGL::Array->new_list (GL_FLOAT, @colors),
      OpenGL::Array->new_list (GL_FLOAT, @texcoords),
      $quad_cnt
   ]
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

