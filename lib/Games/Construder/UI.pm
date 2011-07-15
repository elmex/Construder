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
package Games::Construder::UI;
use common::sense;
require Exporter;
use POSIX qw/floor/;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   ui_text
   ui_title
   ui_border
   ui_subtext
   ui_window
   ui_key
   ui_key_explain
   ui_key_inline_expl
   ui_desc
   ui_subdesc
   ui_caption
   ui_small_text
   ui_hud_window
   ui_hud_window_above
   ui_hud_window_transparent
   ui_hlt_border
   ui_warning
   ui_window_special
   ui_notice
   ui_select_item
   ui_range
   ui_entry
   ui_entry_small
   ui_multiline
   ui_pad_box
/;

=head1 NAME

Games::Construder::UI - Construder Userinterface Theme Definition

=over 4

=cut

our $HIGHLIGHT_BORDER_COLOR = "#ff0000";
our $BORDER_COLOR  = "#8888ff";
our $TITLE_COLOR   = "#8888ff";
our $TEXT_COLOR    = "#ffffff";
our $WARTEXT_COLOR = "#ff0000";
our $NOTICETEXT_COLOR = "#ffffff";
our $SUBTEXT_COLOR = "#ff8888";
our $KEYBIND_COLOR = "#ffff88";
our $BG_COLOR      = "#000022";
our $BG_SEL_COLOR  = "#222244";
our $BG_SEL2_COLOR = "#442222";

sub ui_key {
   my ($key, %args) = @_;
   my $pad = delete $args{pad};
   my $txt =
      ref $key
         ? (join "/", map { "[$_]" } @$key)
         : "[$key]";

   if ($pad == 1) {
      $pad = 20;
      $pad -= length $txt;
      my $hpad = int ($pad / 2);
      my $hpad2 = $pad - $hpad;
      $txt = (" " x $hpad) . $txt . (" " x $hpad2)
   } elsif ($pad == 2) {
      $txt = "$txt ";
   }

   [text => { font => "normal", %args, color => $KEYBIND_COLOR, wrap => -20 },
    $txt
   ]
}
sub ui_title {
   my ($txt, %args) = @_;
   [text => { %args, color => $TITLE_COLOR, font => "big", align => "center", wrap => 30  }, $txt]
}

sub ui_caption {
   my ($txt, %args) = @_;
   [text => { %args, color => $TITLE_COLOR, font => "normal", align => "center"  }, $txt]
}

sub ui_text {
   my ($txt, %args) = @_;
   [text => { wrap => 45, align => "center", %args, color => $TEXT_COLOR }, $txt]
}

sub ui_small_text {
   my ($txt, %args) = @_;
   ui_text ($txt, font => "small", wrap => 70, %args)
}

sub ui_desc {
   my ($desc, %args) = @_;
   ui_text ($desc, align => "center", %args)
}

sub ui_subtext {
   my ($txt, %args) = @_;
   [text => { wrap => 45, align => "center", %args, color => $SUBTEXT_COLOR }, $txt]
}

sub ui_warning {
   my ($txt, %args) = @_;
   [text => { wrap => 20, align => "center", font => "big", color => $WARTEXT_COLOR, %args }, $txt]
}

sub ui_notice {
   my ($txt, %args) = @_;
   [text => { wrap => 20, font => "big", align => "center", color => $NOTICETEXT_COLOR, %args }, $txt]
}

sub ui_subdesc {
   my ($desc, %args) = @_;
   ui_subtext ($desc, align => "center", %args)
}

sub ui_hlt_border {
   my ($hlt, @cont) = @_;
   [box => { dir => "vert", padding => 2, aspect => 1 },
    [box => { dir => "vert", aspect => 1,
              border => {
                 color => ($hlt ? $HIGHLIGHT_BORDER_COLOR : $BORDER_COLOR)
              },
              padding => 2 },
     @cont
    ]
   ]
}

sub ui_border {
   [box => { dir => "vert", padding => 2 },
    [box => { dir => "vert", border => { color => $BORDER_COLOR }, padding => 8 },
     @_
    ]
   ]
}

sub ui_pad_box {
   my ($dir, @childs) = @_;
   [box => { dir => $dir, align => "center" },
      map { [box => { padding => 4, align => $_->[1]->{align} }, $_] } @childs
   ]
}

sub ui_select_item {
   my ($name, $tag, @cont) = @_;
   [select_box => {
      dir => "hor", align => "center", arg => $name, tag => $tag,
      padding => 2, bgcolor => $BG_SEL_COLOR,
      border => { color => $BORDER_COLOR, width => 2 },
      select_border => { color => $HIGHLIGHT_BORDER_COLOR, width => 2 },
    },
    @cont
   ]
}

sub ui_range {
   my ($arg, $min, $max, $step, $fmt, $val) = @_;
   [range => {
       align => "center",
       fmt => $fmt,
       color => $TEXT_COLOR,
       font => "normal",
       arg => $arg,
       step => $step,
       range => [$min, $max],
       highlight => [$BG_COLOR, $BG_SEL_COLOR]
    }, $val]
}

sub ui_entry_small {
   my ($arg, $txt, $maxchars) = @_;
   [entry => { font => 'small', color => $TEXT_COLOR, arg => $arg,
               align => "center",
               (defined $maxchars ? (max_chars => $maxchars) : ()),
               highlight => [$BG_COLOR, $BG_SEL_COLOR] },
    $txt]
}


sub ui_entry {
   my ($arg, $txt, $maxchars) = @_;
   [entry => { font => 'normal', color => $TEXT_COLOR, arg => $arg,
               align => "center",
               (defined $maxchars ? (max_chars => $maxchars) : ()),
               highlight => [$BG_COLOR, $BG_SEL_COLOR] },
    $txt]
}

sub ui_multiline {
   my ($arg, $txt, %arg) = @_;
   [
      multiline => {
            font => 'normal', color => "#ffffff", arg => $arg,
            highlight => [$BG_COLOR, $BG_SEL_COLOR, $BG_SEL2_COLOR],
            max_chars => 32, wrap => -32,
            height => 25, %arg
      },
      $txt
   ],
}


sub ui_key_inline_expl {
   my ($key, $desc, %args) = @_;
   [box => { dir => "hor", align => "center" },
      ui_key ($key, pad => 2, font => "small"),
      ui_text ($desc, align => "left", wrap => 40, font => "small")
   ]
}

sub ui_key_explain {
   my ($key, $desc, %args) = @_;
   [box => { dir => "hor", align => "left" },
      ui_key ($key, pad => 1),
      ui_text ($desc, wrap => 30, align => "left")
   ]
}

sub ui_window_special {
   my ($title, $pos, @content) = @_;
   {
      window => { pos => $pos, bgcolor => $BG_COLOR },
      layout => ui_border (
         ui_title ($title),
         @content
      )
   }

}

sub ui_window {
   my ($title, @content) = @_;
   ui_window_special ($title, [ center => "center" ], @content)
}

sub ui_hud_window_transparent {
   my ($pos, @content) = @_;
   {
      window => { pos => $pos, bgcolor => $BG_COLOR, sticky => 1, alpha => 0.5 },
      layout => [ box => { dir => "vert" },
         @content
      ]
   }
}

sub ui_hud_window {
   my ($pos, @content) = @_;
   {
      window => { pos => $pos, bgcolor => $BG_COLOR, sticky => 1, alpha => 0.65 },
      layout => [ box => { dir => "vert" },
         @content
      ]
   }
}

sub ui_hud_window_above {
   my ($pos, @content) = @_;
   {
      window => { force_one_higher => 1, pos => $pos, bgcolor => $BG_COLOR, sticky => 1, alpha => 0.65 },
      layout => [ box => { dir => "vert" },
         @content
      ]
   }
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

