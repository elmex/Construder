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
   ui_desc
   ui_subdesc
   ui_caption
   ui_small_text
/;

=head1 NAME

Games::Construder::UI - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

our $BORDER_COLOR  = "#8888ff";
our $TITLE_COLOR   = "#8888ff";
our $TEXT_COLOR    = "#ffffff";
our $SUBTEXT_COLOR = "#ff8888";
our $KEYBIND_COLOR = "#ffff88";
our $BG_COLOR      = "#000000";

sub ui_key {
   my ($key, %args) = @_;
   my $pad = delete $args{pad};
   my $txt =
      ref $key
         ? (join "/", map { "[$_]" } @$key)
         : "[$key]";

   if ($pad) {
      $pad = 20;
      $pad -= length $txt;
      my $hpad = int ($pad / 2);
      my $hpad2 = $pad - $hpad;
      $txt = (" " x $hpad) . $txt . (" " x $hpad2)
   }

   [text => { %args, color => $KEYBIND_COLOR, font => "normal", wrap => -20 },
    $txt
   ]
}
sub ui_title {
   my ($txt, %args) = @_;
   [text => { %args, color => $TITLE_COLOR, font => "big", align => "center"  }, $txt]
}

sub ui_caption {
   my ($txt, %args) = @_;
   [text => { %args, color => $TITLE_COLOR, font => "normal", align => "center"  }, $txt]
}

sub ui_text {
   my ($txt, %args) = @_;
   [text => { wrap => 45, %args, color => $TEXT_COLOR }, $txt]
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
   [text => { wrap => 45, %args, color => $SUBTEXT_COLOR }, $txt]
}

sub ui_subdesc {
   my ($desc, %args) = @_;
   ui_subtext ($desc, align => "center", %args)
}

sub ui_border {
   [box => { dir => "vert", padding => 2 },
    [box => { dir => "vert", border => { color => $BORDER_COLOR }, padding => 8 },
     @_
    ]
   ]
}

sub ui_key_explain {
   my ($key, $desc, %args) = @_;
   [box => { dir => "hor" },
      ui_key ($key, pad => 1),
      ui_text ($desc, wrap => 40)
   ]
}

sub ui_window {
   my ($title, @content) = @_;
   {
      window => { pos => [ center => "center" ], background => $BG_COLOR },
      layout => ui_border (
         ui_title ($title),
         @content
      )
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

