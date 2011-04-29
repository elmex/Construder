package Games::Blockminer3D::Client::UI;
use common::sense;
use SDL;
use SDL::Surface;
use SDL::Video;
use SDL::TTF;
use OpenGL qw(:all);

use base qw/Object::Event/;

=head1 NAME

Games::Blockminer3D::Client::UI - A simple and small GUI library for the game

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Client::UI->new (%args)

=cut

my $BIG_FONT; # should be around 35 pixel
my $NORM_FONT; # should be around 20 pixel
my $SMALL_FONT; # should be around 10 pixel

sub init_ui {
   unless (SDL::Config->has('SDL_ttf')) {
      Carp::cluck("SDL_ttf support has not been compiled");
   }

   my $font = 'res/FreeMonoBold.ttf';

   unless (SDL::TTF::was_init()) {
      SDL::TTF::init () == 0
         or Carp::cluck "SDL::TTF could not be initialized: "
            . SDL::get_error . "\n";
   }

   warn "INIT UI\n";
   $BIG_FONT   = SDL::TTF::open_font ('res/FreeMonoBold.ttf', 35)
      or die "Couldn't load font from res/FreeMonoBold.ttf: " . SDL::get_error . "\n";
   $NORM_FONT = SDL::TTF::open_font ('res/FreeMonoBold.ttf', 20)
      or die "Couldn't load font from res/FreeMonoBold.ttf: " . SDL::get_error . "\n";
   $SMALL_FONT = SDL::TTF::open_font ('res/FreeMonoBold.ttf', 10)
      or die "Couldn't load font from res/FreeMonoBold.ttf: " . SDL::get_error . "\n";
}

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;

   $self->{opengl_texture_size} = 512;

   return $self
}

sub _clr2color {
   my ($clr) = @_;
   if ($clr =~ /#(..)(..)(..)(..)?/) {
      #d#if ($4 ne '') {
      #d#   return (hex ($1), hex ($2), hex ($3), hex ($4))
      #d#} else {
         return (hex ($1), hex ($2), hex ($3))
      #d#}
   }
   return (0, 0, 0);
}

sub window_pos_to_coords {
   my ($self) = @_;
   my $pos  = $self->{desc}->{window}->{pos};
   my $size = $self->{desc}->{window}->{size};

   if ($pos eq 'up_left') {
      return [0, 0];
   } elsif ($pos eq 'down_left') {
      return [0, $self->{H} - $size->[1]];
   } elsif ($pos eq 'up_right') {
      return [$self->{W} - $size->[0], 0];
   } elsif ($pos eq 'down_right') {
      return [$self->{W} - $size->[0], $self->{H} - $size->[1]];
   } elsif ($pos eq 'center') {
      my ($rw, $rh) = ($self->{W} - $size->[0], $self->{H} - $size->[1]);
      $rw = int ($rw / 2);
      $rh = int ($rh / 2);
      return [$rw, $rh];
   } else {
      return $pos;
   }
}

sub place_text {
   my ($self, $pos, $size, $text, $font, $color) = @_;

   my $fnt = $font eq 'big' ? $BIG_FONT : $font eq 'small' ? $SMALL_FONT : $NORM_FONT;

   my $surf = $self->{sdl_surf};
   my $avail_h = $size->[1];
   my $line_skip = SDL::TTF::font_line_skip ($fnt);

   my $curp = $pos;
   for my $line (split /\n/, $text) {
      my $tsurf = SDL::TTF::render_utf8_blended (
         $fnt, $line, SDL::Color->new (_clr2color ($color)));

      my $h = $tsurf->h < $avail_h ? $tsurf->h : $avail_h;
      #d# warn "PLACE $line: $avail_h : $line_skip : $h\n";
      SDL::Video::blit_surface (
         $tsurf, SDL::Rect->new (0, 0, $tsurf->w, $h),
         $surf,  SDL::Rect->new (@$curp, $size->[0], $h));

      $avail_h   -= $line_skip;
      if ($avail_h < 0) {
         last;
      }
      $curp->[1] += $line_skip;
   }
}

sub update {
   my ($self, $gui_desc) = @_;

   $self->{desc} = $gui_desc if defined $gui_desc;
   $gui_desc = $self->{desc};
   my $win = $gui_desc->{window};
   $self->prepare_opengl_texture;
   $self->prepare_sdl_surface; # creates a new sdl surface for this window

   for my $el (@{$gui_desc->{elements}}) {

      if ($el->{type} eq 'text') {
         $self->place_text ($el->{pos}, $el->{size}, $el->{text}, $el->{font}, $el->{color});
         # render text

      } elsif ($el->{type} eq 'text_entry') {
         $self->place_text_entry (
            $el->{pos}, $el->{size}, $el->{text}, $el->{edit_key}, $el->{color});
         $self->register_query (
            $el->{edit_key}, $el->{name}, $el->{label} => "line");

      } elsif ($el->{type} eq 'text_field') {
         $self->place_text_entry (
            $el->{pos}, $el->{size},
            $el->{text}, $el->{edit_key},
            $el->{color}, $el->{skipped_lines});

         $self->register_local_shortcut ("down" => sub {
            $el->{skipped_lines}++;
            $self->update;
         });
         $self->register_local_shortcut ("down" => sub {
            $el->{skipped_lines}--;
            $el->{skipped_lines} = 0 if $el->{skipped_lines} < 0;
            $self->update;
         });

         $self->register_query (
            $el->{edit_key}, $el->{name}, $el->{label} => "text");

      } elsif ($el->{type} eq 'gauge') {
         $self->place_gauge (
            $el->{pos}, $el->{size}, $el->{label}, $el->{fill}, $el->{color}
         );

      } elsif ($el->{type} eq 'model') {
         $self->place_model (
            $el->{pos}, $el->{size}, $el->{number}, $el->{label}
         );
      }
   }

   $self->render_view; # refresh rendering to opengl texture
}

sub prepare_opengl_texture {
   my ($self) = @_;
   return if $self->{gl_id};

   my ($nr) = glGenTextures_p (1);
   $self->{gl_id} = $nr;
}

sub prepare_sdl_surface {
   my ($self) = @_;
   my $size = $self->{opengl_texture_size};
   $self->{sdl_surf} = SDL::Surface->new (
      SDL_SWSURFACE, $size, $size, 24, 0, 0, 0);
   my $clr = SDL::Video::map_RGB (
      $self->{sdl_surf}->format,
      _clr2color ($self->{desc}->{window}->{color}),
   );
   SDL::Video::fill_rect (
      $self->{sdl_surf},
      SDL::Rect->new (0, 0, $self->{sdl_surf}->w, $self->{sdl_surf}->h),
      $clr
   );
}

sub _get_texfmt {
   my ($surface) = @_;
   my $ncol = $surface->format->BytesPerPixel;
   my $rmsk = $surface->format->Rmask;
   #d# warn "SURF $ncol ; " . sprintf ("%02x", $rmsk) . "\n";
   ($ncol == 4 ? ($rmsk == 0x000000ff ? GL_RGBA : GL_BGRA)
               : ($rmsk == 0x000000ff ? GL_RGB  : GL_BGR))
}

sub render_view {
   my ($self) = @_;

   my $surf = $self->{sdl_surf};
   my $texture_format = _get_texfmt ($surf);

   glBindTexture (GL_TEXTURE_2D, $self->{gl_id});
   glTexParameterf (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
   glTexParameterf (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

   SDL::Video::lock_surface($surf);
   gluBuild2DMipmaps_s (GL_TEXTURE_2D,
      $surf->format->BytesPerPixel,
      $surf->w, $surf->h,
      $texture_format, GL_UNSIGNED_BYTE,
      ${$surf->get_pixels_ptr});

   SDL::Video::unlock_surface($surf);

   $self->{rendered} = 1;
}

sub display {
   my ($self) = @_;

   return unless $self->{rendered};

   my $wins = $self->{desc}->{window}->{size};
   my ($u, $v) = (
      $wins->[0] / $self->{opengl_texture_size},
      $wins->[1] / $self->{opengl_texture_size}
   );

   my ($pos) = $self->window_pos_to_coords;
   my ($size)  = $self->{desc}->{window}->{size};

   glPushMatrix;
   glTranslatef (@$pos, 0);
   glColor4d (1, 1, 1, $self->{desc}->{window}->{alpha});
   glBindTexture (GL_TEXTURE_2D, $self->{gl_id});
   glBegin (GL_QUADS);

   glTexCoord2d(0, $v);
   glVertex3d (0, $size->[1], 0);

   glTexCoord2d($u, $v);
   glVertex3d ($size->[0], $size->[1], 0);

   glTexCoord2d($u, 0);
   glVertex3d ($size->[0], 0, 0);

   glTexCoord2d(0, 0);
   glVertex3d (0, 0, 0);

   glEnd ();
   glPopMatrix;
}

sub DESTROY {
   my ($self) = @_;
   glDestroyTextures_p (delete $self->{gl_id}) if $self->{gl_id};
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

