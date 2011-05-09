package Games::Blockminer3D::Client::Renderer;
use common::sense;
use Games::Blockminer3D::Client::MapChunk;
use OpenGL qw/:all/;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   render_visible_quads
   render_quads
   render_object_type_sample
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

sub render_visible_quads_2 {
#   my ($x, $y, $z) = @_;
#
#   my @visible = Games::Blockminer3D::World::chunk_visible_cells ($x, $y, $z);
#
#   my (@vertexes, @colors, @texcoords);
#
#   my $quad_cnt;
#   FACES:
#   for (my $z = 0; $z < $CHNK_SIZE; $z++) {
#      for (my $y = 0; $y < $CHNK_SIZE; $y++) {
#         for (my $x = 0; $x < $CHNK_SIZE; $x++) {
#            my ($cur, $top, $bot, $left, $right, $front, $back)
#               = Games::Blockminer3D::Client::MapChunk::_neighbours ($map, $x, $y, $z);
#            next unless $cur->[2];
#            if ($cur->[0] != 0) {
#               my @faces;
#               my ($txtid, $surf, $uv, $model) = $RES->obj2texture ($cur->[0]);
#
#               if ($model) {
#                  unless ($model_cache{$cur->[0]}) {
#                     $model_cache{$cur->[0]} = _render_model (@$model);
#                  }
#                  my ($verts, $txtcoords) = @{$model_cache{$cur->[0]}};
#
#                  my $color = $cur->[1] / 15;
#                  for (@$verts) {
#                     push @vertexes, (
#                        $_->[0] + $x, $_->[1] + $y, $_->[2] + $z
#                     );
#                     push @colors, (
#                        $color, $color, $color,
#                     );
#                  }
#                  $quad_cnt += scalar (@$verts) / 4;
#                  push @texcoords, @$txtcoords;
#                  next;
#               }
#
#               push @faces, [0, $front->[1] / 15] if $front->[4];
#               push @faces, [1, $top->[1] / 15]   if $top->[4];
#               push @faces, [2, $back->[1] / 15]  if $back->[4];
#               push @faces, [3, $left->[1] / 15]  if $left->[4];
#               push @faces, [4, $right->[1] / 15] if $right->[4];
#               push @faces, [5, $bot->[1] / 15]   if $bot->[4];
#
#               for (@faces) {
#                  my ($faceidx, $color) = @$_;
#                  $quad_cnt++;
#                  push @vertexes, map {
#                     my $v = $vertices[$indices[$faceidx * 4 + $_]];
#                     (
#                        $v->[0] + $x,
#                        $v->[1] + $y,
#                        $v->[2] + $z,
#                     )
#                  } 0..3;
#                  push @colors, (
#                     $color, $color, $color,
#                     $color, $color, $color,
#                     $color, $color, $color,
#                     $color, $color, $color,
#                  );
#                  push @texcoords, (
#                     $uv->[2], $uv->[3],
#                     $uv->[2], $uv->[1],
#                     $uv->[0], $uv->[1],
#                     $uv->[0], $uv->[3],
#                  );
#               }
#            }
#         }
#      }
#   }
#   warn "GOT: " . scalar (@vertexes) . " verts, " . scalar (@colors) . " colors and " . scalar (@texcoords) . " texcoords and $quad_cnt quads\n";
# #d#  warn "LIST[@vertexes | @colors | @texcoords]\n";
#
#   [
#      OpenGL::Array->new_list (GL_FLOAT, @vertexes),
#      OpenGL::Array->new_list (GL_FLOAT, @colors),
#      OpenGL::Array->new_list (GL_FLOAT, @texcoords),
#      $quad_cnt
#   ]
}


sub _neighbours {
   my ($x, $y, $z) = @_;

   (
      Games::Blockminer3D::World::at ($x,     $y,     $z),
      Games::Blockminer3D::World::at ($x,     $y + 1, $z),
      Games::Blockminer3D::World::at ($x,     $y - 1, $z),
      Games::Blockminer3D::World::at ($x - 1, $y,     $z),
      Games::Blockminer3D::World::at ($x + 1, $y,     $z),
      Games::Blockminer3D::World::at ($x,     $y,     $z),
      Games::Blockminer3D::World::at ($x,     $y,     $z - 1),
      Games::Blockminer3D::World::at ($x,     $y,     $z + 1),

#      _map_get_if_exists ($map, $x, $y,     $z),
#      _map_get_if_exists ($map, $x, $y + 1, $z),
#      _map_get_if_exists ($map, $x, $y - 1, $z),
#      _map_get_if_exists ($map, $x - 1, $y, $z),
#      _map_get_if_exists ($map, $x + 1, $y, $z),
#      _map_get_if_exists ($map, $x, $y,     $z - 1),
#      _map_get_if_exists ($map, $x, $y,     $z + 1),
   )
}

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

sub render_object_type_sample {
   my ($type) = @_;
   my ($txtid, $surf, $uv, $model) = $RES->obj2texture ($type);
   my ($verts, $txtcoord);

   if ($model) {
      unless ($model_cache{$type}) {
         $model_cache{$type} = _render_model (@$model);
      }
      ($verts, $txtcoord) = @{$model_cache{$type}};

   } else {
      ($verts, $txtcoord) = @{_render_model (1, [1, $type])};
   }

   my @verts = map { @$_ } @$verts;

   my $quads = [
      OpenGL::Array->new_list (GL_FLOAT, @verts),
      OpenGL::Array->new_list (GL_FLOAT, map { (1, 1, 1) } @$verts),
      OpenGL::Array->new_list (GL_FLOAT, @$txtcoord),
      @verts / 12 # 3 * 4 vertices
   ];
   #d# warn "sample quads: $quads->[3] | $type | @$model | @verts | @$txtcoord\n";
   render_quads ($quads)
}

sub render_quads {
   my ($quads) = @_;
   my ($txtid) = $RES->obj2texture (1);

   glBindTexture (GL_TEXTURE_2D, $txtid);
   glEnableClientState(GL_VERTEX_ARRAY);
   glEnableClientState(GL_COLOR_ARRAY);
   glEnableClientState(GL_TEXTURE_COORD_ARRAY);

   glVertexPointer_p (3, $quads->[0]);
   glColorPointer_p (3, $quads->[1]);
   glTexCoordPointer_p (2, $quads->[2]);
   for (0..($quads->[3] - 1)) {
      glDrawArrays (GL_QUADS, $_ * 4, 4);
   }
   glDisableClientState(GL_COLOR_ARRAY);
   glDisableClientState(GL_VERTEX_ARRAY);
   glDisableClientState(GL_TEXTURE_COORD_ARRAY);
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

