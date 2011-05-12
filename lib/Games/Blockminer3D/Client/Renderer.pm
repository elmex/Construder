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

sub render_object_type_sample {
   my ($type) = @_;
   my ($txtid, $surf, $uv, $model) = $RES->obj2texture ($type);
   my ($verts, $txtcoord);

   my (@vert, @color, @txt);
   if ($model) {
      Games::Blockminer3D::Renderer::model (
         $type, 1, 0, 0, 0, \@vert, \@color, \@txt
      );
 #  } else {
  #    ($verts, $txtcoord) = @{_render_model (1, [1, $type])};
   }

   my $quads = [
      OpenGL::Array->new_list (GL_FLOAT, @vert),
      OpenGL::Array->new_list (GL_FLOAT, @color),
      OpenGL::Array->new_list (GL_FLOAT, @txt),
      @vert / 12 # 3 * 4 vertices
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

