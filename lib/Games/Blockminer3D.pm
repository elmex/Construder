package Games::Blockminer3D;
use common::sense;

our $VERSION = '0.01';

use XSLoader;
XSLoader::load "Games::Blockminer3D", $Games::Blockminer3D::VERSION;

=head1 NAME

Games::Blockminer3D - 3D block building game written in Perl

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   return $self
}


package Games::Blockminer3D::VolDraw;

my %OPS = (
   add  => 1,
   sub  => 2,
   mul  => 3,
   set  => 4,
   set_if_0 => 5,
   set_if_1 => 6,
);

sub lerp {
   my ($a, $b, $x) = @_;
   $a * (1 - $x) + $b * $x
}

sub draw_commands {
   my ($str, $env) = @_;

   my (@lines) = grep { not (/^\s*#/) } split /\r?\n/, $str;
   my (@stmts) = map { split /\s*;\s*/, $_ } @lines;


# noise umbennen: fill (erkl]ert mehr)
# ; erlauben
# zeichenpuffer direkt "selecten"
   for (@stmts) {
      s/^\s+//;
      next if $_ eq '';

      my ($cmd, @arg) = split /\s+/, $_;

      (@arg) = map {
            $_ =~ /P([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)/
               ? lerp ($1, $2, $env->{param})
               : ($_ eq 'P' ?  $env->{param} : $_)
      } @arg;

      if ($cmd eq 'mode') {
         set_op ($OPS{$arg[0]});

      } elsif ($cmd eq 'dst') { # set destination buffer (0..3)
         set_dst ($arg[0]);

      } elsif ($cmd eq 'src') { # set source buffer (0..3)
         set_src ($arg[0]);

      } elsif ($cmd eq 'src_blend') {
         # amount with which source will be blended,
         # negative amount will invert the drawn colors
         $arg[0] = 1 unless $arg[0] ne '';
         set_src_blend ($arg[0]);

      } elsif ($cmd eq 'fill') {
         # fill with either color or
         # draw destination buffer over itself (allows blending with src_blend)
         if ($arg[0] ne '') {
            val ($arg[0]);
         } else {
            dst_self ();
         }

      } elsif ($cmd eq 'fill_noise') {
         # fill destination with noise
         # fill_noise <octaves> <scale factor> <persistence> <seed offset>
         fill_simple_noise_octaves ($env->{seed} + $arg[3], $arg[0], $arg[1], $arg[2]);

      } elsif ($cmd eq 'spheres') {
         # draw spheres
         # spheres <recursion-cnt>
         sphere_subdiv (0, 0, 0, $env->{size}, $arg[0]);

      } elsif ($cmd eq 'menger_sponge') {
         # draw menger sponge <level> <src blend & gradient direction>
         menger_sponge_box (0, 0, 0, $env->{size}, $arg[0]);

      } elsif ($cmd eq 'cantor_dust') {
         # draw cantor dust <level> <src blend & gradient direction>
         cantor_dust_box (0, 0, 0, $env->{size}, $arg[0]);

      } elsif ($cmd eq 'map_range') {
         # map range of destionation buffer
         map_range ($arg[0], $arg[1], $arg[2], $arg[3]);

      } elsif ($cmd eq 'dst_range') {
         # set modifiable range of destination buffer
         $arg[0] = 0 unless $arg[0] ne '';
         $arg[1] = 0 unless $arg[1] ne '';
         set_dst_range ($arg[0], $arg[1]);

      } elsif ($cmd eq 'src_range') {
         # set range of source color to draw with
         $arg[0] = 0 unless $arg[0] ne '';
         $arg[1] = 0 unless $arg[1] ne '';
         set_src_range ($arg[0], $arg[1]);

      } else {
         warn "unknown draw command: $_\n";
      }
   }
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
