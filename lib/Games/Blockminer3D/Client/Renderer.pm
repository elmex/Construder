package Games::Blockminer3D::Client::Renderer;
use common::sense;
use Games::Blockminer3D::Client::MapChunk;
use OpenGL qw/:all/;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   render_visible_quads
/;

=head1 NAME

Games::Blockminer3D::Client::Renderer - Rendering utility

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

our $RES;
our $CHNK_SIZE = $Games::Blockminer3D::Client::MapChunk::SIZE;

my @indices  = (
   qw/ 0 1 2 3 /, # 0 front
   qw/ 1 5 6 2 /, # 1 top
   qw/ 7 6 5 4 /, # 2 back
   qw/ 4 5 1 0 /, # 3 left
   qw/ 3 2 6 7 /, # 4 right
   qw/ 3 7 4 0 /, # 5 bottom
);

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

sub _render_model {
   my ($dim, @blocks) = @_;

   my $scale = 1 / $dim;
   my @verts;
   my @texcoord;

   my $blk_nr = 1;
   for my $y (0..($dim - 1)) {
      for my $z (0..($dim - 1)) {
         for my $x (0..($dim - 1)) {
            my ($blk) = grep { $blk_nr == $_->[0] } @blocks;
            if ($blk) {
               my ($txtid, $surf, $uv, $model) = $RES->obj2texture ($blk->[1]);

               for my $face (0..5) {
                  push @verts, map {
                     my $v = $vertices[$indices[$face * 4 + $_]];
                     [
                        ($v->[0] + $x) * $scale,
                        ($v->[1] + $y) * $scale,
                        ($v->[2] + $z) * $scale,
                     ]
                  } 0..3;
                  push @texcoord, (
                     $uv->[2], $uv->[3],
                     $uv->[2], $uv->[1],
                     $uv->[0], $uv->[1],
                     $uv->[0], $uv->[3],
                  );
               }
            }
            $blk_nr++;
         }
      }
   }

   [\@verts, \@texcoord]
}

my %model_cache;

sub render_visible_quads {
   my ($map) = @_;

   my (@vertexes, @colors, @texcoords);

   my $quad_cnt;
   FACES:
   for (my $z = 0; $z < $CHNK_SIZE; $z++) {
      for (my $y = 0; $y < $CHNK_SIZE; $y++) {
         for (my $x = 0; $x < $CHNK_SIZE; $x++) {
            my ($cur, $top, $bot, $left, $right, $front, $back)
               = Games::Blockminer3D::Client::MapChunk::_neighbours ($map, $x, $y, $z);
            next unless $cur->[2];
            if ($cur->[0] != 0) {
               my @faces;
               my ($txtid, $surf, $uv, $model) = $RES->obj2texture ($cur->[0]);

               if ($model) {
                  unless ($model_cache{$cur->[0]}) {
                     $model_cache{$cur->[0]} = _render_model (@$model);
                  }
                  my ($verts, $txtcoords) = @{$model_cache{$cur->[0]}};

                  my $color = $cur->[1] / 15;
                  for (@$verts) {
                     push @vertexes, (
                        $_->[0] + $x, $_->[1] + $y, $_->[2] + $z
                     );
                     push @colors, (
                        $color, $color, $color,
                     );
                  }
                  $quad_cnt += scalar (@$verts) / 4;
                  push @texcoords, @$txtcoords;
                  next;
               }

               push @faces, [0, $front->[1] / 15] if $front->[4];
               push @faces, [1, $top->[1] / 15]   if $top->[4];
               push @faces, [2, $back->[1] / 15]  if $back->[4];
               push @faces, [3, $left->[1] / 15]  if $left->[4];
               push @faces, [4, $right->[1] / 15] if $right->[4];
               push @faces, [5, $bot->[1] / 15]   if $bot->[4];

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
                  );
               }
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

