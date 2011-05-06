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

   $self->{opengl_texture_size} = 1024;
   $self->prepare_opengl_texture;

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

sub _calc_extents {
   my ($ext, $base_w, $base_h) = @_;
   my ($pos, $size) = ([$ext->[0], $ext->[1]], [$ext->[2], $ext->[3]]);

   $size = [$size->[0] * $base_w, $size->[1]] if $size->[0] <= 1;
   $size = [$size->[0], $size->[1] * $base_h] if $size->[1] <= 1;
   $size = [int $size->[0], int $size->[1]];

   if ($pos->[0] eq 'left') {
      $pos->[0] = 0;
   } elsif ($pos->[0] eq 'right') {
      $pos->[0] = ($base_w - $size->[0]);
   } elsif ($pos->[0] eq 'center') {
      $pos->[0] = int (($base_w - $size->[0]) / 2);
   } elsif ($pos->[0] <= 1) {
      $pos->[0] = $base_w * $pos->[0];
   }

   if ($pos->[1] eq 'up') {
      $pos->[1] = 0;
   } elsif ($pos->[1] eq 'down') {
      $pos->[1] = ($base_h - $size->[1]);
   } elsif ($pos->[1] eq 'center') {
      $pos->[1] = int (($base_h - $size->[1]) / 2);
   } elsif ($pos->[1] <= 1) {
      $pos->[1] = $base_h * $pos->[1];
   }

   $pos = [int $pos->[0], int $pos->[1]];

   ($pos, $size)
}

sub window_e {
   my ($self) = @_;
}

sub render_text {
   my ($self, $text, $wrap, $font, $color) = @_;
}

sub place_text {
   my ($self, $ext, $align, $wrap, $text, $font, $color) = @_;

   my ($pos, $size) = _calc_extents ($ext, @{$self->{window_size}});

   my $fnt = $font eq 'big' ? $BIG_FONT : $font eq 'small' ? $SMALL_FONT : $NORM_FONT;

   my $surf = $self->{sdl_surf};
   my $avail_h = $size->[1];
   my $line_skip = SDL::TTF::font_line_skip ($fnt);

   my @lines = split /\n/, $text;
   if ($wrap) {
      my ($min_w) = @{ SDL::TTF::size_utf8 ($fnt, "mmmmm") };
      my @ilines = @lines;
      (@lines) = ();
      while (@ilines) {
         my $l = shift @ilines;
         my ($w, $h) = @{ SDL::TTF::size_utf8 ($fnt, $l) };
         while ($w > $size->[0] && $w > $min_w) {
            # FIXME: this substr works on utf encoded strings, not unicode strings
            #        it WILL destroy multibyte encoded characters!
            $ilines[0] = (substr $l, -1, 1, '') . $ilines[0];
            ($w) = @{ SDL::TTF::size_utf8 ($fnt, $l) };
         }
         push @lines, $l;
      }
   }

   my $curp = $pos;
   for my $line (@lines) {
      my $tsurf = SDL::TTF::render_utf8_blended (
         $fnt, $line, SDL::Color->new (_clr2color ($color)));

      my $h = $tsurf->h < $avail_h
                 ? $tsurf->h
                 : $avail_h;

      my $woffs = 0;
      if ($align eq 'center') {
         $woffs = int (($size->[0] - $tsurf->w) / 2)
            if $tsurf->w < $size->[0];

      } elsif ($align eq 'right') {
         $woffs = $size->[0] - $tsurf->w
            if $tsurf->w < $size->[0];
      }

      #d# warn "PLACE $line: $avail_h : $line_skip : $h\n";
      SDL::Video::blit_surface (
         $tsurf, SDL::Rect->new (0, 0, $tsurf->w, $h),
         $surf,  SDL::Rect->new ($curp->[0] + $woffs, $curp->[1], $size->[0], $h));

      $avail_h -= $line_skip;
      $curp->[1] += $line_skip;
      last if $avail_h < 0;
   }
}

sub update {
   my ($self, $gui_desc) = @_;

   $self->{desc} = $gui_desc if defined $gui_desc;
   $gui_desc = $self->{desc};
   my $win = $gui_desc->{window};

   ($self->{window_pos}, $self->{window_size}) =
      _calc_extents ($win->{extents}, $self->{W}, $self->{H});

   $self->prepare_sdl_surface; # creates a new sdl surface for this window

   $self->{commands}   = $gui_desc->{commands};
   $self->{command_cb} = $gui_desc->{command_cb};
   $self->{sticky}     = $win->{sticky};

   for my $el (@{$gui_desc->{elements}}) {

      if ($el->{type} eq 'text') {
         $self->place_text ($el->{extents}, $el->{align}, $el->{wrap}, $el->{text}, $el->{font}, $el->{color});
         # render text

      } elsif ($el->{type} eq 'entry') {
         $self->place_text ($el->{pos}, $el->{size}, $el->{text}, $el->{font}, $el->{color});

      } elsif ($el->{type} eq 'image') {
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
   unless ($self->{sdl_surf}) {
      $self->{sdl_surf} = SDL::Surface->new (
         SDL_SWSURFACE, $size, $size, 24, 0, 0, 0);
   }

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
   glTexImage2D_s (GL_TEXTURE_2D,
      0, $surf->format->BytesPerPixel, $surf->w, $surf->h,
      0, $texture_format, GL_UNSIGNED_BYTE, ${$surf->get_pixels_ptr});

   SDL::Video::unlock_surface($surf);

   $self->{rendered} = 1;
}

sub display {
   my ($self) = @_;

   return unless $self->{rendered};

   my ($pos, $size) = ($self->{window_pos}, $self->{window_size});
   my $wins = [@$size];
   my ($u, $v) = (
      $wins->[0] / $self->{opengl_texture_size},
      $wins->[1] / $self->{opengl_texture_size}
   );

   glPushMatrix;
   glTranslatef (@$pos, 0);
   glColor4f (1, 1, 1, $self->{desc}->{window}->{alpha});
   glBindTexture (GL_TEXTURE_2D, $self->{gl_id});
   glBegin (GL_QUADS);

   glTexCoord2f(0, $v);
   glVertex3f (0, $size->[1], 0);

   glTexCoord2f($u, $v);
   glVertex3f ($size->[0], $size->[1], 0);

   glTexCoord2f($u, 0);
   glVertex3f ($size->[0], 0, 0);

   glTexCoord2f(0, 0);
   glVertex3f (0, 0, 0);

   glEnd ();
   glPopMatrix;
}

sub input_key_press : event_cb {
   my ($self, $key, $name, $unicode, $rhandled) = @_;
 #  warn "UNICODE ($key, $name) $unicode\n";
   my $cmd;
   if ($name eq 'escape') {
      $cmd = "cancel" unless $self->{sticky};
   } elsif ($self->{commands}) {
      $cmd = $self->{commands}->{default_keys}->{$name}
   }
   if ($cmd ne '') {
      $self->{command_cb}->($cmd) if $self->{command_cb};
      $$rhandled = $cmd eq 'cancel' ? 2 : 1;
   }
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

