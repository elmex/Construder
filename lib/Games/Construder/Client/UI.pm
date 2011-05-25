package Games::Construder::Client::UI;
use common::sense;
use SDL;
use SDL::Surface;
use SDL::Video;
use SDL::TTF;
use OpenGL qw(:all);
use JSON;
use Games::Construder::Client::Renderer;
use Games::Construder::Vector;

use base qw/Object::Event/;

=head1 NAME

Games::Construder::Client::UI - A simple and small GUI library for the game

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Construder::Client::UI->new (%args)

=cut

my $BIG_FONT; # should be around 35 pixel
my $NORM_FONT; # should be around 20 pixel
my $SMALL_FONT; # should be around 12 pixel

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
   $SMALL_FONT = SDL::TTF::open_font ('res/FreeMonoBold.ttf', 12)
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

sub animation_step {
   my ($self) = @_;
   $self->{anim_state} = not $self->{anim_state};
   if (@{$self->{active_elements}}) {
      $self->update;
   }
}

sub _fnt2font {
   my $fnt = shift;
   $fnt eq 'big' ? $BIG_FONT : $fnt eq 'small' ? $SMALL_FONT : $NORM_FONT;
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

sub window_position {
   my ($self, $pos, $size) = @_;

   my ($sw, $sh) = ($self->{W}, $self->{H});
   my ($x, $y, $ro_x, $ro_y) = @$pos;

   if ($x eq 'right') {
      $x = $sw - $size->[0];
   } elsif ($x eq 'center') {
      $x = ($sw - $size->[0]) / 2;
   } else {
      $x = 0;
   }

   if ($y eq 'down') {
      $y = $sh - $size->[1];
   } elsif ($y eq 'center') {
      $y = ($sh - $size->[1]) / 2;
   } else {
      $y = 0;
   }

   $x += $ro_x * $sw;
   $y += $ro_y * $sh;

   [int ($x), int ($y)]
}

sub layout_text {
   my ($font, $text, $wrap, $txtalign, $line_range, $min_chars) = @_;
   my $layout = {
      font => $font
   };

   my @lines     = split /\n/, $text;
   my $line_skip = SDL::TTF::font_line_skip ($font);

   my $txt_w;

   if ($wrap) {
      my ($max_w) = @{ SDL::TTF::size_utf8 ($font, "m" x $wrap) };
      $txt_w = $max_w;

      my @ilines = @lines;
      (@lines) = ();

      while (@ilines) {
         my $l = shift @ilines;
         my ($w, $h) = @{ SDL::TTF::size_utf8 ($font, $l) };

         while ($w > $max_w) {
            # FIXME: this substr works on utf encoded strings, not unicode strings
            #        it WILL destroy multibyte encoded characters!
            $ilines[0] = (substr $l, -1, 1, '') . $ilines[0];
            ($w) = @{ SDL::TTF::size_utf8 ($font, $l) };
         }
         push @lines, $l;
      }
   } else {
      for my $l (@lines) {
         my ($w, $h) = @{ SDL::TTF::size_utf8 ($font, $l) };
         $txt_w = $w if $txt_w < $w;
      }
   }

   if ($line_range) {
      splice @lines, 0, $line_range->[0];
      splice @lines, ($line_range->[1] - $line_range->[0]) + 1;
   }

   my $txt_h;
   for my $l (@lines) {
      my ($w, $h) = @{ SDL::TTF::size_utf8 ($font, $l) };

      if ($txtalign eq 'center') {
         push @{$layout->{lines}}, [($txt_w - $w) / 2, $txt_h, $l];

      } elsif ($txtalign eq 'right') {
         push @{$layout->{lines}}, [$txt_w - $w, $txt_h, $l];

      } else {
         push @{$layout->{lines}}, [0, $txt_h, $l];
      }

      $txt_h += $line_skip;
   }

   if (defined $min_chars) {
      my ($w) = @{ SDL::TTF::size_utf8 ($font, "m" x $min_chars) };
      $txt_w = $w if $txt_w < $w;
   }

   $layout->{size} = [$txt_w, $txt_h];

   $layout
}

sub add_entry {
   my ($self, $el) = @_;
   push @{$self->{active_elements}}, $el;
}

sub setup_sizes {
   my ($self, $el) = @_;
   my ($type, $attr, @childs) = @$el;

   if ($type eq 'box') {
      my ($mw, $mh);

      for (@childs) {
         my $size = $self->setup_sizes ($_);
         if ($attr->{dir} eq 'vert') {
            $mw = $size->[0] if $mw < $size->[0];
            $mh += $size->[1];
         } else {
            $mw += $size->[0];
            $mh = $size->[1] if $mh < $size->[1];
         }
      }

      $attr->{padding_y} = $attr->{padding} unless defined $attr->{padding_y};

      $attr->{size} = [$mw + $attr->{padding} * 2,
                       $mh + $attr->{padding_y} * 2];
      $attr->{inner_size} = [$mw, $mh];
      return $attr->{size};

   } elsif ($type eq 'text' || $type eq 'entry') {
      if ($type eq 'entry') {
         $self->add_entry ($el);
      }

      my ($fnt) = element_font ($el);
      my $lyout =
         layout_text ($fnt, $childs[0], $attr->{wrap},
                      $attr->{align}, $attr->{line_range},
                      $attr->{max_chars});

      $attr->{size}   = $lyout->{size};
      $attr->{layout} = $lyout;
      return $attr->{size}
   }
}

sub draw_text {
   my ($self, $pos, $layout, $color) = @_;

   my $font = $layout->{font};
   my $surf = $self->{sdl_surf};

   my $curp = [@$pos];
   for my $line (@{$layout->{lines}}) {
      my ($x, $y, $txt) = @$line;

      my $tsurf = SDL::TTF::render_utf8_blended (
         $layout->{font}, $txt, SDL::Color->new (_clr2color ($color)));

      unless ($tsurf) {
         warn "SDL::TTF::render_utf8_blended could not render \"$line\": "
              . SDL::get_error . "\n";
         next;
      }

      SDL::Video::blit_surface (
         $tsurf, SDL::Rect->new (0, 0, $tsurf->w, $tsurf->h),
         $surf,  SDL::Rect->new ($pos->[0] + $x, $pos->[1] + $y, $tsurf->w, $tsurf->h));
   }
}

sub draw_box {
   my ($self, $pos, $size, $bgcolor, $border) = @_;

   if ($bgcolor) {
      my $clr = SDL::Video::map_RGB (
         $self->{sdl_surf}->format, _clr2color ($bgcolor)
      );
      SDL::Video::fill_rect (
         $self->{sdl_surf},
         SDL::Rect->new (@$pos, @$size),
         $clr
      );
   }

   if ($border) {
      my $clr = SDL::Video::map_RGB (
         $self->{sdl_surf}->format, _clr2color ($border->{color}),
      );

      my $w = $border->{width} || 1;
      my ($x, $y, $bw, $bh) = (@$pos, @$size);

      SDL::Video::fill_rect (
         $self->{sdl_surf}, SDL::Rect->new ($x, $y, $w, $bh), $clr
      );
      SDL::Video::fill_rect (
         $self->{sdl_surf}, SDL::Rect->new ($x + ($bw - $w), $y, $w, $bh), $clr
      );
      SDL::Video::fill_rect (
         $self->{sdl_surf}, SDL::Rect->new ($x, $y, $bw, $w), $clr
      );
      SDL::Video::fill_rect (
         $self->{sdl_surf}, SDL::Rect->new ($x, $y + ($bh - $w), $bw, $w), $clr
      );
   }
}

sub draw_element {
   my ($self, $el, $offs) = @_;
   my ($type, $attr, @childs) = @$el;

   if ($type eq 'box') {
      $self->draw_box ($offs, $attr->{size}, $attr->{bgcolor}, $attr->{border});

      my $loffs = [$offs->[0] + $attr->{padding}, $offs->[1] + $attr->{padding_y}];
      my $isize = $attr->{inner_size};

      my $x = $loffs->[0];
      my $y = $loffs->[1];

      if ($attr->{dir} eq 'vert') {
         for (@childs) {
            my $size = $_->[1]->{size};
            my $pos  = [$x, $y];

            if ($_->[1]->{align} eq 'center') {
               $pos->[0] += ($isize->[0] - $size->[0]) / 2;
            } elsif ($_->[1]->{align} eq 'right') {
               $pos->[0] += $isize->[0] - $size->[0];
            }

            $self->draw_element ($_, $pos);
            $y += $size->[1];
         }

      } else {
         for (@childs) {
            my $size = $_->[1]->{size};
            my $pos  = [$x, $y];

            if ($_->[1]->{align} eq 'center') {
               $pos->[1] += ($isize->[1] - $size->[1]) / 2;
            } elsif ($_->[1]->{align} eq 'right') {
               $pos->[1] += $isize->[1] - $size->[1];
            }

            $self->draw_element ($_, $pos);
            $x += $size->[0];
         }
      }

   } elsif ($type eq 'text') {
      $self->draw_text ($offs, $attr->{layout}, $attr->{color});

   } elsif ($type eq 'entry') {
      $self->draw_text (
         $offs, $attr->{layout},
         ($self->{active_element} eq $el && $self->{anim_state}
            ? $attr->{active_color}
            : $attr->{color}));
   }
}

sub element_font {
   my ($el) = @_;
   my $font = $el->[1]->{font};
   $font eq 'big' ? $BIG_FONT : $font eq 'small' ? $SMALL_FONT : $NORM_FONT;
}

sub update {
   my ($self, $gui_desc) = @_;

   $self->{desc} = $gui_desc if defined $gui_desc;
   $gui_desc = $self->{desc};
   my $win = $gui_desc->{window};

   $self->{element_offset} = 0;
   $self->{relative_extents} = [];

   $self->{commands}   = $gui_desc->{commands};
   $self->{command_cb} = $gui_desc->{command_cb};
   $self->{sticky}     = $win->{sticky};
   $self->{models}     = [];

   $self->{entries}    = [];

   unless ($gui_desc->{layout}) {
      warn "Warning: Got GUI Windows without layout!";
      return;
   }

   unless ($self->{layout}) {
      $self->{layout} = decode_json (encode_json ($gui_desc->{layout}));
   }
   my $layout = $self->{layout};

   $self->{active_elements} = [];
   my $size = $self->setup_sizes ($layout);
   $self->{layout} = $layout;
   $self->{window_size} = $size;
   $self->{window_pos}  = $self->window_position ($win->{pos}, $size);

   unless (grep {
             $self->{active_element} eq $_
           } @{$self->{active_elements}}
   ) {
      $self->{active_element} = $self->{active_elements}->[0];
   }

   # window_size_inside is initialized here, and window_padding too
   $self->prepare_sdl_surface; # creates a new sdl surface for this window

   $self->draw_element ($layout, [0, 0]);

   $self->render_view; # refresh rendering to opengl texture
}

sub switch_active {
   my ($self, $dir) = @_;
   return unless @{$self->{active_elements}};

   if ($dir < 0) {
      my $last = $self->{active_elements}->[-1];
      for (@{$self->{active_elements}}) {
         if ($_ eq $self->{active_element}) {
            $self->{active_element} = $last;
         }
         $last = $_;
      }
   } else {
      my $next = $self->{active_elements}->[0];
      for (reverse @{$self->{active_elements}}) {
         if ($_ eq $self->{active_element}) {
            $self->{active_element} = $next;
         }
         $next = $_;
      }
   }

   $self->update;
}

sub prepare_opengl_texture {
   my ($self) = @_;
   return if $self->{gl_id};

   my ($nr) = glGenTextures_p (1);
   $self->{gl_id} = $nr;
   $self->{gl_texture} = 0;
}

sub prepare_sdl_surface {
   my ($self, $clear_color) = @_;

   $clear_color = "#000000" unless defined $clear_color;

   my $size = $self->{opengl_texture_size};
   unless ($self->{sdl_surf}) {
      $self->{sdl_surf} = SDL::Surface->new (
         SDL_SWSURFACE, $size, $size, 24, 0, 0, 0);
   }
   my $clr = SDL::Video::map_RGB (
      $self->{sdl_surf}->format, _clr2color ($clear_color),
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
   #if ($self->{gl_texture}) {
   #   glTexSubImage2D_s (GL_TEXTURE_2D,
   #      0, 0, 0, $surf->w, $surf->h,
   #      $texture_format, GL_UNSIGNED_BYTE, ${$surf->get_pixels_ptr});

   #} else {
      # without SubImage it seems to be faster in nytprof...
      glTexImage2D_s (GL_TEXTURE_2D,
         0, $surf->format->BytesPerPixel, $surf->w, $surf->h,
         0, $texture_format, GL_UNSIGNED_BYTE, ${$surf->get_pixels_ptr});
    #  $self->{gl_texture} = 1;
   #}
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
   my $z = -8;
   glTranslatef (@$pos, $z);
   my $a = $self->{desc}->{window}->{alpha};
   $a = 1 unless defined $a;
   glColor4f (1, 1, 1, $a);
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

   for (@{$self->{models}}) {
      my ($pos, $size, $model) = @$_;
      glPushMatrix;
      my ($w, $h) = ($size->[0] * 0.3, $size->[1] * 0.3);
      glTranslatef ($pos->[0], $pos->[1] + ($h * 1.25), -1);
      glScalef ($w, $h, 0.01);
      glScalef (1, -1, 1);
      glRotatef (45, 1, 0, 0);
      glRotatef (45, 0, 1, 0);

      render_object_type_sample ($_->[2]);
      glPopMatrix;
   }
}

sub input_key_press : event_cb {
   my ($self, $key, $name, $unicode, $rhandled) = @_;
 #  warn "UNICODE ($key, $name) $unicode\n";
   my $cmd;
   if ($name eq 'escape') {
      $cmd = "cancel" unless $self->{sticky};

   } elsif (defined $self->{active_element}) {
      my $el = $self->{active_element};

      warn "UNICO $name: [$unicode]\n";

      if ($name eq 'backspace' || $name eq 'delete') {
         chop $el->[2];
         warn "CHOP $el->[2]\n",
         $self->update;
         $$rhandled = 1;
         return;

      } elsif ($name eq 'down') {
         $self->switch_active (1);
         $$rhandled = 1;
         return;

      } elsif ($name eq 'up') {
         $self->switch_active (-1);
         $$rhandled = 1;
         return;

      } elsif ($self->{commands} && $self->{commands}->{default_keys}->{$name}) {
         $cmd = $self->{commands}->{default_keys}->{$name}

      } elsif ($unicode ne '') {
         if (
            not ($el->[1]->{max_chars} && length ($el->[2]) >= $el->[1]->{max_chars})
            && $unicode =~ /^([A-Za-z0-9]+)$/
         ) {
            $el->[2] .= $unicode;
         }
         $self->update;
         $$rhandled = 1;
         return;
      }
   } elsif ($self->{commands} && $self->{commands}->{default_keys}->{$name}) {
      $cmd = $self->{commands}->{default_keys}->{$name}
   }

   if ($cmd ne '') {
      my $arg;
      if (@{$self->{entries}}) {
         $arg = [map { $_->{text} } @{$self->{entries}}];
         warn "ARG @$arg\n";
      }
      $self->{command_cb}->($cmd, $arg) if $self->{command_cb};
      $$rhandled = $cmd eq 'cancel' ? 2 : 1;
   }
}

sub DESTROY {
   my ($self) = @_;
   glDeleteTextures_p (delete $self->{gl_id}) if $self->{gl_id};
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

