# Games::Construder - A 3D Game written in Perl with an infinite and modifiable world.
# Copyright (C) 2011  Robin Redeker
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
package Games::Construder::Client::UI;
use common::sense;
use SDL;
use SDL::Surface;
use SDL::Video;
use SDL::TTF;
use OpenGL qw(:all);
use JSON;
use Games::Construder::Vector;
use Games::Construder;
use File::ShareDir::PAR;
use Games::Construder::Logging;

use base qw/Object::Event/;

=head1 NAME

Games::Construder::Client::UI - Client GUI implementation

=over 4

=cut

our $RES; # set by Games::Construder::Client

my $BIG_FONT; # should be around 35 pixel
my $NORM_FONT; # should be around 20 pixel
my $SMALL_FONT; # should be around 12 pixel

sub init_ui {
   unless (SDL::Config->has('SDL_ttf')) {
      Carp::cluck("SDL_ttf support has not been compiled");
   }

   unless (SDL::TTF::was_init()) {
      SDL::TTF::init () == 0
         or Carp::cluck "SDL::TTF could not be initialized: "
            . SDL::get_error . "\n";
   }

   my $fnt =
      File::ShareDir::PAR::dist_file ('Games-Construder', 'font/FreeMonoBold.ttf');

   $BIG_FONT   = SDL::TTF::open_font ($fnt, 35)
      or die "Couldn't load font from $fnt: " . SDL::get_error . "\n";
   $NORM_FONT = SDL::TTF::open_font ($fnt, 20)
      or die "Couldn't load font from $fnt: " . SDL::get_error . "\n";
   $SMALL_FONT = SDL::TTF::open_font ($fnt, 12)
      or die "Couldn't load font from $fnt: " . SDL::get_error . "\n";
}

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;

   $self->{opengl_texture_size} = 1024;

   return $self
}

sub pre_resize_screen {
   my ($self) = @_;
   glDeleteTextures_p (delete $self->{gl_id})
      if $self->{gl_id};
}

sub resize_screen {
   my ($self, $w, $h) = @_;
   $self->{W} = $w;
   $self->{H} = $h;
}

sub animation_step {
   my ($self) = @_;
   $self->{anim_state} = not $self->{anim_state};
   $self->{anim_step}++;
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

   my @lines     = split /\n/, $text, -1;
   my $line_skip = SDL::TTF::font_line_skip ($font);

   my $txt_w;

   if ($wrap > 0) { # word wrapping
      my @olines;
      for (@lines) {
         my @words = split /\s+/, $_;
         my $line = "";
         my $force = 0;
         while (@words) {
            my $w = shift @words;
            my $new_line = $line . "$w ";

            if ($force || length ($new_line) <= $wrap) {
               $line = $new_line;
               $force = 0;

            } else {
               push @olines, $line;
               $line = "";
               unshift @words, $w;
               $force = 1;
            }
         }
         push @olines, $line;
      }
      (@olines) = map { s/\s*$//; $_ } @olines;

      my $max_w;
      for (@olines) {
         next if $_ eq '';
         my ($w) = @{ SDL::TTF::size_utf8 ($font, $_) };
         $max_w = $w if $max_w < $w;
      }
      $txt_w = $max_w;

      (@lines) = @olines;

   } elsif ($wrap < 0) { # character wrapping
      $wrap = -$wrap;
      my @olines;
      for my $line (@lines) {
         while (length ($line) > $wrap) {
            push @olines, substr $line, 0, $wrap, "";
         }
         push @olines, $line;
      }

      my $max_w;
      for (@olines) {
         next if $_ eq '';
         my ($w) = @{ SDL::TTF::size_utf8 ($font, $_) };
         $max_w = $w if $max_w < $w;
      }
      $txt_w = $max_w;

      (@lines) = @olines;

   } else {
      for my $l (@lines) {
         next if $l eq '';
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
      $txt_h = $line_skip if $txt_h < $line_skip;
   }

   $layout->{size} = [$txt_w, $txt_h];

   $layout
}

sub add_active {
   my ($self, $el) = @_;
   push @{$self->{active_elements}}, $el;
}

sub setup_sizes {
   my ($self, $el) = @_;
   my ($type, $attr, @childs) = @$el;

   if ($type eq 'box' || $type eq 'select_box') {
      if ($type eq 'select_box') {
         $self->add_active ($el);
      }

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

      if ($attr->{aspect}) {
         my $max = $mh;
         $max = $mw if $max < $mw;
         ($mw, $mh) = ($max, $max);
      }

      $attr->{padding_y} = $attr->{padding} unless defined $attr->{padding_y};

      $attr->{size} = [$mw + $attr->{padding} * 2,
                       $mh + $attr->{padding_y} * 2];
      $attr->{inner_size} = [$mw, $mh];
      return $attr->{size};

   } elsif ($type eq 'text' || $type eq 'entry' || $type eq 'range' || $type eq 'multiline') {
      if ($type eq 'entry' || $type eq 'range' || $type eq 'multiline') {
         if ($type eq 'multiline') {
            $self->do_multiline ($el);
            ($type, $attr, @childs) = @$el;
         }
         $self->add_active ($el);
      }

      my ($fnt) = element_font ($el);
      my $fmt = $attr->{fmt} ne '' ? $attr->{fmt} : "%s";
      my $txt =
         $type eq 'range'
            ? "< " . sprintf ($fmt, $childs[0]) . " >" 
            : sprintf ($fmt, $childs[0]);
      my $lyout =
         layout_text ($fnt, $txt, $attr->{wrap},
                      $attr->{align}, $attr->{line_range},
                      $attr->{max_chars});

      $attr->{size}   = $lyout->{size};
      $attr->{layout} = $lyout;
      return $attr->{size}

   } elsif ($type eq 'model') {
      return $attr->{size} = [$attr->{width}, $attr->{width}];
   }
}

sub draw_text {
   my ($self, $pos, $layout, $color) = @_;

   my $font = $layout->{font};
   my $surf = $self->{sdl_surf};

   my $curp = [@$pos];
   for my $line (@{$layout->{lines}}) {
      my ($x, $y, $txt) = @$line;
      next if $txt eq '';

      my $tsurf = SDL::TTF::render_utf8_blended (
         $layout->{font}, $txt, SDL::Color->new (_clr2color ($color)));

      unless ($tsurf) {
         warn "SDL::TTF::render_utf8_blended could not render \"$txt\": "
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

   if ($type eq 'box' || $type eq 'select_box') {
      my ($bgcolor, $border) = ($attr->{bgcolor}, $attr->{border});
      if ($type eq 'select_box'
          && $self->{active_element} eq $el
      ) {
         $bgcolor = $attr->{select_bgcolor}
            if $attr->{select_bgcolor};
         $border = $attr->{select_border}
            if $attr->{select_border};
      }

      $self->draw_box ($offs, $attr->{size}, $bgcolor, $border);

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
      if ($self->{active_element} eq $el) {
         $self->draw_box (
            $offs, $attr->{size},
            ($self->{anim_state} ? $attr->{highlight}->[0] : $attr->{highlight}->[1]));
      }
      $self->draw_text ($offs, $attr->{layout}, $attr->{color});

   } elsif ($type eq 'multiline') {
      if ($self->{active_element} eq $el) {
         if ($attr->{active_input}) {
            $self->draw_box ($offs, $attr->{size}, $attr->{highlight}->[2]);
         } else {
            $self->draw_box ($offs, $attr->{size}, $attr->{highlight}->[1]);
         }
      } else {
         $self->draw_box ($offs, $attr->{size}, $attr->{highlight}->[0]);
      }
      $self->draw_text ($offs, $attr->{layout}, $attr->{color});

   } elsif ($type eq 'range') {
      if ($self->{active_element} eq $el) {
         $self->draw_box (
            $offs, $attr->{size},
            ($self->{anim_state} ? $attr->{highlight}->[0] : $attr->{highlight}->[1]));
      }
      $self->draw_text ($offs, $attr->{layout}, $attr->{color});

   } elsif ($type eq 'model') {
      push @{$self->{models}}, [$offs, $attr->{size}, $childs[0], $attr->{animated}];
   }
}

sub element_font {
   my ($el) = @_;
   my $font = $el->[1]->{font};
   $font eq 'big' ? $BIG_FONT : $font eq 'small' ? $SMALL_FONT : $NORM_FONT;
}

sub fit_size_pot {
   my ($size) = @_;
   my $gls = 1;
   $gls++ while $size->[0] > (2**$gls) || $size->[1] > (2**$gls);
   2**$gls
}

sub update {
   my ($self, $gui_desc) = @_;

   if (defined $gui_desc) {
      delete $self->{key_repeat};
      $self->{desc} = $gui_desc;
   }

   my $win = $self->{desc}->{window};

   $self->{element_offset} = 0;
   $self->{relative_extents} = [];

   $self->{commands}   = $self->{desc}->{commands};
   $self->{command_cb} = $self->{desc}->{command_cb};
   $self->{sticky}     = $win->{sticky};
   $self->{models}     = [];

   $self->{entries}    = [];

   if ($gui_desc && $gui_desc->{layout}) {
      $self->{layout} = decode_json (encode_json ($gui_desc->{layout}));
   }

   my $layout = $self->{layout};

   $self->{active_elements} = [];

   my $size;
   $size = $self->setup_sizes ($layout);
   $self->{layout} = $layout;
   $self->{window_size} = $size;
   $self->{window_pos}  = $self->window_position ($win->{pos}, $size);
   $self->{opengl_texture_size} = fit_size_pot ($size);

   unless (grep {
             $self->{active_element} eq $_
           } @{$self->{active_elements}}
   ) {
      $self->{active_element} = $self->{active_elements}->[0];
   }

   $self->prepare_opengl_texture;

   # window_size_inside is initialized here, and window_padding too
   $self->prepare_sdl_surface ($win->{bgcolor}, $size); # creates a new sdl surface for this window

   ctr_prof ("draw elements", sub {
      $self->draw_element ($layout, [0, 0]);
   });

   ctr_prof ("render_view", sub {
      $self->render_view; # refresh rendering to opengl texture
   });
}

sub active {
   my ($self, $act) = @_;
   $self->{active} = $act;
   delete $self->{key_repeat};
}

sub switch_active {
   my ($self, $dir) = @_;
   return unless @{$self->{active_elements}};

   if ($dir < 0) {
      my $last = $self->{active_elements}->[-1];
      for (@{$self->{active_elements}}) {
         if ($_ eq $self->{active_element}) {
            $self->{active_element} = $last;
            last;
         }
         $last = $_;
      }
   } else {
      my $next = $self->{active_elements}->[0];
      for (reverse @{$self->{active_elements}}) {
         if ($_ eq $self->{active_element}) {
            $self->{active_element} = $next;
            last;
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
   my ($self, $clear_color, $winsize) = @_;

   $clear_color = "#000000" unless defined $clear_color;

   my $size = $self->{opengl_texture_size};
   delete $self->{sdl_surf}
      if $self->{surf_size} != $size;

   unless ($self->{sdl_surf}) {
      $self->{sdl_surf} = SDL::Surface->new (
         SDL_SWSURFACE, $size, $size, 24, 0, 0, 0);
      $self->{surf_size} = $size;
      $self->{gl_texture} = 0;
   }

   ctr_prof ("prepsurf($size)", sub {
      my $clr = SDL::Video::map_RGB (
         $self->{sdl_surf}->format, _clr2color ($clear_color),
      );
      SDL::Video::fill_rect (
         $self->{sdl_surf},
         SDL::Rect->new (0, 0, @$winsize),
         $clr
      );
   });

}

sub _get_texfmt {
   my ($surface) = @_;
   my $ncol = $surface->format->BytesPerPixel;
   my $rmsk = $surface->format->Rmask;
   #d# warn "SURF $ncol ; " . sprintf ("%02x", $rmsk) . "\n";
   ($ncol == 4 ? ($rmsk == 0x000000ff ? GL_RGBA : GL_BGRA)
               : ($rmsk == 0x000000ff ? GL_RGB  : GL_BGR))
}

our %MODEL_CACHE;

sub render_object_type_sample {
   my ($type, $skip) = @_;

   my ($txtid) = $RES->obj2texture (1);
   glBindTexture (GL_TEXTURE_2D, $txtid);

   if ($skip >= 0) {
      $skip++;
      my $geom = Games::Construder::Renderer::new_geom ();
      Games::Construder::Renderer::model ($type, 0, 1, 0, 0, 0, $geom, $skip, 1);
      Games::Construder::Renderer::draw_geom ($geom);
      Games::Construder::Renderer::free_geom ($geom);
      return;
   }

   if (my $g = $MODEL_CACHE{$type}) {
      Games::Construder::Renderer::draw_geom ($g);

   } else {
      my $geom = $MODEL_CACHE{$type} = Games::Construder::Renderer::new_geom ();
      Games::Construder::Renderer::model ($type, 0, 1, 0, 0, 0, $geom, -1, 0);
      Games::Construder::Renderer::draw_geom ($geom);
   }
}

sub render_view {
   my ($self) = @_;

   my $surf = $self->{sdl_surf};
   my $texture_format = _get_texfmt ($surf);

   glBindTexture (GL_TEXTURE_2D, $self->{gl_id});
   glTexParameterf (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
   glTexParameterf (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

   SDL::Video::lock_surface($surf);
   if ($self->{gl_texture}) {
      glTexSubImage2D_s (GL_TEXTURE_2D,
         0, 0, 0, $surf->w, $surf->h,
         $texture_format, GL_UNSIGNED_BYTE, ${$surf->get_pixels_ptr});

   } else {
      # without SubImage it seems to be faster in nytprof...
      glTexImage2D_s (GL_TEXTURE_2D,
         0, $surf->format->BytesPerPixel, $surf->w, $surf->h,
         0, $texture_format, GL_UNSIGNED_BYTE, ${$surf->get_pixels_ptr});
      $self->{gl_texture} = 1;
   }
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
   $z-- if $self->{sticky};
   $z += 0.5 if $self->{desc}->{window}->{force_one_higher};
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

   for (@{$self->{models}}) {
      my ($pos, $size, $model, $anim) = @$_;

      glPushMatrix;
      my ($w, $h) = ($size->[0] * 0.65, $size->[1] * 0.65);
      glTranslatef ($pos->[0] + ($h * 0.05), $pos->[1] + ($h * 1.2), $self->{sticky} ? 0.5 : 1);
      glScalef ($w, $h, 0.01);
      glScalef (1, -1, 1);
      glRotatef (25, 1, 0, 0);
      glRotatef (45, 0, 1, 0);

      if ($anim) {
         my $model_blocks = $RES->type_model_blocks ($_->[2]);
         render_object_type_sample ($_->[2], $self->{anim_step} % $model_blocks);
      } else {
         render_object_type_sample ($_->[2], -1);
      }
      glPopMatrix;
   }

   glPopMatrix;
}

our @MLBUFFER;

sub do_multiline {
   my ($self, $el, $key, $name, $unicode) = @_;

   my $ml = ($el->[3]      ||= { text => $el->[2], l_offs => 0 });
   my $c  = ($ml->{cursor} ||= []);

   my (@lines) = split /\r?\n/, $ml->{text}, -1;

   my $hdl = 0;

   if ($name eq 'up') {
      $c->[0]--;
      $hdl = 1;
   } elsif ($name eq 'down') {
      $c->[0]++;
      $hdl = 1;
   } elsif ($name eq 'left') {
      $c->[1]--;
      $hdl = 1;
   } elsif ($name eq 'right') {
      $c->[1]++;
      $hdl = 1;
   } elsif ($name eq 'home') {
      $c->[1] = 0;
      $hdl = 1;
   } elsif ($name eq 'end') {
      $c->[1] = 99999;
      $hdl = 1;
   } elsif ($name eq 'f2') {
      (@MLBUFFER) = ($lines[$c->[0]]);
      $hdl = 1;

   } elsif ($name eq 'f3') {
      push @MLBUFFER, $lines[$c->[0]];
      $c->[0]++;
      $hdl = 1;

   } elsif ($name eq 'f4') {
      push @MLBUFFER, splice @lines, $c->[0], 1;
      $hdl = 1;

   } elsif ($name eq 'f5') {
      splice @lines, $c->[0], 0, @MLBUFFER;
      $hdl = 1;

   } elsif ($name eq 'f6') {
      (@MLBUFFER) = ();
      $hdl = 1;

   } elsif ($name eq 'backspace') {
      if ($c->[1] > 0) {
         substr $lines[$c->[0]], $c->[1] - 1, 1, '';
         $c->[1]--;

      } elsif ($c->[0] > 0) {
         my $pl = length $lines[$c->[0] - 1];
         $lines[$c->[0] - 1] .= splice @lines, $c->[0], 1, ();
         $c->[0]--;
         $c->[1] = $pl;
      }
      $hdl = 1;

   } elsif ($name eq 'delete') {
      if ($c->[1] == length ($lines[$c->[0]])) {
         $lines[$c->[0]] .= splice @lines, $c->[0] + 1, 1, ();
      } else {
         substr $lines[$c->[0]], $c->[1], 1, '';
      }
      $hdl = 1;

   } elsif ($name eq 'return') {
      my $rest = substr $lines[$c->[0]], $c->[1];
      $lines[$c->[0]] = substr $lines[$c->[0]], 0, $c->[1];
      splice @lines, $c->[0] + 1, 0, $rest;
      $c->[0]++;
      $c->[1] = 0;
      $hdl = 1;

   } elsif ($unicode =~ /(\p{IsWord}|\p{IsSpace}|\p{IsPunct}|[[:punct:]])/) {
      substr $lines[$c->[0]], $c->[1], 0, $unicode;
      $c->[1]++;
      $hdl = 1;

   } else {
      $hdl = 1;
   }

   $c->[0] = 0 if $c->[0] < 0;
   if (@lines) {
      $c->[0] = (@lines - 1) if $c->[0] >= @lines;
   } else {
      $c->[0] = 0;
   }

   $c->[1] = 0 if $c->[1] < 0;
   $c->[1] = length ($lines[$c->[0]]) if $c->[1] > length ($lines[$c->[0]]);

   $ml->{text} = join "\n", @lines;
   substr $lines[$c->[0]], $c->[1], 0, "|";
   $el->[2] = join "\n", @lines;

   $hdl
}

sub input_key_press : event_cb {
   my ($self, $key, $name, $unicode, $rhandled) = @_;
   ctr_log (debug => "UI(%s) keypress %s/%s/%d", $self->{name}, $key, $name, ord $unicode);
   my $cmd;

   my $el = $self->{active_element};
   if ($el && $el->[1]->{active_input} && $name eq 'escape') {
      $el->[1]->{active_input} = 0;
      $$rhandled = 1;
      $self->update;
      $cmd = "save_text";

   } elsif ($name eq 'escape') {
      $cmd = "cancel" unless $self->{sticky};

   } elsif (defined $self->{active_element}) {
      my $el = $self->{active_element};

      if ($el->[0] eq 'multiline' && $el->[1]->{active_input} && $self->do_multiline ($el, $key, $name, $unicode)) {
         $$rhandled = 1;
         $self->update;
         return;

      } elsif ($el->[0] eq 'multiline' && not ($el->[1]->{active_input}) && $name eq 'return') {
         $el->[1]->{active_input} = 1;
         $$rhandled = 1;
         $self->update;
         return;

      } elsif ($el->[0] eq 'entry' && ($name eq 'backspace' || $name eq 'delete')) {
         chop $el->[2];
         $self->update;
         $$rhandled = 1;
         return;

      } elsif ($el->[0] eq 'range' && ($name eq 'left' || $name eq 'right')) {
         $el->[2] += ($name eq 'left' ? -1 : 1) * $el->[1]->{step};
         if ($el->[2] < $el->[1]->{range}->[0]) {
            $el->[2] = $el->[1]->{range}->[0];
         }
         if ($el->[2] > $el->[1]->{range}->[1]) {
            $el->[2] = $el->[1]->{range}->[1];
         }
         $self->update;
         $$rhandled = 1;
         return;

      } elsif ($name eq 'down' || $name eq 'tab' || $name eq 'right') {
         $self->switch_active (1);
         $$rhandled = 1;
         return;

      } elsif ($name eq 'up' || $name eq 'left') {
         $self->switch_active (-1);
         $$rhandled = 1;
         return;

      } elsif ($self->{commands} && $self->{commands}->{default_keys}->{$name}) {
         $cmd = $self->{commands}->{default_keys}->{$name}

      } elsif ($el->[0] eq 'entry'
               && $unicode =~ /(\p{IsWord}|\p{IsSpace}|\p{IsPunct}|[[:punct:]])/
      ) {
         warn "UNICODE ADD:'".ord ($unicode)."'\n";
         if (
            not ($el->[1]->{max_chars} && length ($el->[2]) >= $el->[1]->{max_chars})
            && ($el->[1]->{allowed_chars} ne ''
                   ? $unicode =~ /^([$el->[1]->{allowed_chars}]+)$/
                   : 1)
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
      if (@{$self->{active_elements}}) {
         $arg = {
            map {
               my @a;
               if ($_->[0] eq 'entry') {
                  (@a) = ($_->[1]->{arg} => $_->[2]);
               } elsif ($_->[0] eq 'multiline') {
                  (@a) = ($_->[1]->{arg} => $_->[3]->{text});
               } elsif ($_->[0] eq 'range') {
                  (@a) = ($_->[1]->{arg} => $_->[2]);
               }
               @a
            } @{$self->{active_elements}}
         };

         if ($self->{active_element}->[0] eq 'select_box') {
            $arg->{$self->{active_element}->[1]->{arg}} =
               $self->{active_element}->[1]->{tag};
         }
      }

      $self->{command_cb}->($cmd, $arg, $self->{commands}->{need_selected_boxes})
         if $self->{command_cb};
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

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License.

=cut

1;

