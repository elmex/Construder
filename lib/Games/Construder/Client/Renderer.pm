package Games::Construder::Client::Renderer;
use common::sense;
use Games::Construder::Client::MapChunk;
use OpenGL qw/:all/;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   render_quads
   render_object_type_sample
/;

=head1 NAME

Games::Construder::Client::Renderer - Rendering utility

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

our $RES;

our %MODEL_CACHE;

sub render_object_type_sample {
   my ($type) = @_;

   my ($txtid) = $RES->obj2texture (1);
   glBindTexture (GL_TEXTURE_2D, $txtid);

   if (my $g = $MODEL_CACHE{$type}) {
      Games::Construder::Renderer::draw_geom ($g);

   } else {
      my $geom = $MODEL_CACHE{$type} = Games::Construder::Renderer::new_geom ();
      Games::Construder::Renderer::model ($type, 1, 0, 0, 0, $geom);
      Games::Construder::Renderer::draw_geom ($geom);
   }
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

