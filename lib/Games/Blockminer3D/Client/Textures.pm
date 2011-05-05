package Games::Blockminer3D::Client::Textures;
use common::sense;
use File::Temp qw/tempfile/;
use SDL::Image;
use SDL::Video;
use OpenGL qw(:all);

=head1 NAME

Games::Blockminer3D::Client::Textures - Manage textures for the Client

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Client::Textures->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   return $self
}

sub _get_texfmt {
   my ($surface) = @_;
   my $ncol = $surface->format->BytesPerPixel;
   my $rmsk = $surface->format->Rmask;
   ($ncol == 4 ? ($rmsk == 0x000000ff ? GL_RGBA : GL_BGRA)
               : ($rmsk == 0x000000ff ? GL_RGB  : GL_BGR))
}

sub _data2surface {
   my ($data) = @_;
   my ($fh, $fname) = tempfile (SUFFIX => '.png');
   binmode $fh, ':raw';
   print $fh $data;
   close $fh;

   my $img = SDL::Image::load ($fname)
      or die "Couldn't load texture from '$fname': " . SDL::get_error () . "\n";
   $img
}

sub _pixel2uv {
   my ($uv, $w, $h) = @_;
   $uv->[0] /= $w;
   $uv->[2] /= $w;
   $uv->[1] /= $h;
   $uv->[3] /= $h;
}

sub add_file {
   my ($self, $name, $catalog) = @_;
   open my $fh, "<", $name
      or die "Couldn't open '$name': $!\n";
   binmode $fh, ":raw";
   my $cont = do { local $/; <$fh> };
   $self->add ($cont, $catalog);
}

sub add {
   my ($self, $data, $catalog) = @_;

   my $id = glGenTextures_p(1);
   my $surf = _data2surface ($data);

   SDL::Video::lock_surface ($surf);
   my $texture_format = _get_texfmt ($surf);

   glBindTexture (GL_TEXTURE_2D, $id);
   glTexParameterf (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
   glTexParameterf (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

   gluBuild2DMipmaps_s (GL_TEXTURE_2D,
      $surf->format->BytesPerPixel, $surf->w, $surf->h, $texture_format,
      GL_UNSIGNED_BYTE, ${$surf->get_pixels_ptr});

   SDL::Video::unlock_surface ($surf);

   for (@$catalog) {
      my ($nr, $uv, $md5) = @$_; # md5 for future use
      $uv = [0, 0, $surf->w, $surf->h] unless defined $uv;
      $uv = [@$uv];
      _pixel2uv ($uv, $surf->w, $surf->h);
      warn "TEXTURE ADDED $nr : @$uv : $id\n";
      $self->{textures}->[$nr] = [$id, $uv, $surf];
   }
}

sub get_opengl {
   my ($self, $nr) = @_;
   @{$self->{textures}->[$nr] || []}
}

sub get_sdl {
   my ($self, $nr) = @_;
   ($self->{textures}->[$nr] || [])->[2]
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

