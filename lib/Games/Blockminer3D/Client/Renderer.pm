package Games::Blockminer3D::Client::Renderer;
use common::sense;
use Games::Blockminer3D::Client::MapChunk;
use OpenGL qw/:all/;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
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

