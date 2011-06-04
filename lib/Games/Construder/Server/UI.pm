package Games::Construder::Server::UI;
use common::sense;
require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   ui_player_score
   ui_player_bio_warning
/;

=head1 NAME

Games::Construder::Server::UI - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

sub ui_player_score {
   my ($score, $hl) = @_;
   {
      window => {
         sticky  => 1,
         pos     => [center => "up"],
         alpha   => $hl ? 1 : 0.6,
      },
      layout => [
         box => {
            border  => { color => $hl ? "#ff0000" : "#777700" },
            padding => ($hl ? 10 : 2),
            align   => "hor",
         },
         [text => {
            font  => "normal",
            color => "#aa8800",
            align => "center"
          }, "Score:"],
         [text => {
            font  => "big",
            color => $hl ? "#ff0000" : "#aa8800",
          }, ($score . ($hl ? "+$hl" : ""))]
      ]
   }
}

sub ui_player_bio_warning {
   my ($seconds) = @_;

   {
      window => {
         sticky => 1,
         pos    => [center => 'center', 0, -0.15],
         alpha  => 0.3,
      },
      layout => [
         box => { dir => "vert" },
         [text => { font => "big", color => "#ff0000", wrap => 28, align => "center" },
          "Warning: Bio energy level low! You have $seconds seconds left!\n"],
         [text => { font => "normal", color => "#ff0000", wrap => 35, align => "center" },
          "Death imminent, please dematerialize something that provides bio energy!"],
      ]
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

