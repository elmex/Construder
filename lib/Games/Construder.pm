package Games::Construder;
use JSON;
use common::sense;

our $VERSION = '0.01';

use XSLoader;
XSLoader::load "Games::Construder", $Games::Construder::VERSION;

=head1 NAME

Games::Construder - 3D block building game written in Perl

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Construder->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   return $self
}

package Games::Construder::VolDraw;

sub _get_file {
   my ($file) = @_;
   open my $f, "<", $file
      or die "Couldn't open '$file': $!\n";
   binmode $f, ":raw";
   do { local $/; <$f> }
}

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

sub show_map_range {
   my ($a, $b) = @_;
   map_range (0, $a - 0.000001, 0, 0);
   map_range ($b + 0.000001, 2, 0, 0);
   map_range ($a, $b, 0, 0.6); # enhance contrast a bit maybe
}

sub draw_commands {
   my ($str, $env) = @_;

   $env->{seed}++; # offset by 1, so we get no 0 should be unsigned anyways

   my (@lines) = map { $_ =~ s/#.*$//; $_ } split /\r?\n/, $str;
   my (@stmts) = map { split /\s*;\s*/, $_ } @lines;

# noise umbennen: fill (erkl]ert mehr)
# ; erlauben
# zeichenpuffer direkt "selecten"
   for (@stmts) {
      s/^\s+(.*?)\s*$/$1/;
      next if $_ eq '';

      my ($cmd, @arg) = split /\s+/, $_;

      (@arg) = map {
            $_ =~ /P([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)/
               ? lerp ($1, $2, $env->{param})
               : ($_ eq 'P' ?  $env->{param} : $_)
      } @arg;

      if ($cmd eq 'mode') {
         set_op ($OPS{$arg[0]});

      } elsif ($cmd eq 'end') {
         last;

      } elsif ($cmd eq 'src_dst') { # set source and destination buffer (0..3)
         set_src ($arg[0]);
         set_dst ($arg[1]);

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
         # spheres <recursion-cnt> <shrink factor (default 0)>
         subdiv (1, 0, 0, 0, $env->{size}, defined $arg[1] ? $arg[1] : 0, $arg[0]);

      } elsif ($cmd eq 'cubes') {
         # draw spheres
         # cubes <recursion-cnt> <shrink factor (default 0)>
         subdiv (0, 0, 0, 0, $env->{size}, defined $arg[1] ? $arg[1] : 0, $arg[0]);

      } elsif ($cmd eq 'triangles') {
         # draw spheres
         # triangles <recursion-cnt> <shrink factor (default 0)>
         subdiv (2, 0, 0, 0, $env->{size}, defined $arg[1] ? $arg[1] : 0, $arg[0]);

      } elsif ($cmd eq 'self_cubes') {
         # draw spheres
         # spheres <missing corners> <recursion-cnt> <seed offset>
         self_sim_cubes_hash_seed (0, 0, 0, $env->{size}, $arg[0], $env->{seed} + $arg[2], $arg[1]);

      } elsif ($cmd eq 'menger_sponge') {
         # draw menger sponge <level>
         menger_sponge_box (0, 0, 0, $env->{size}, $arg[0]);

      } elsif ($cmd eq 'cantor_dust') {
         # draw cantor dust <level>
         cantor_dust_box (0, 0, 0, $env->{size}, $arg[0]);

      } elsif ($cmd eq 'sierpinski_pyramid') {
         # sierpinski_pyramid <level>
         sierpinski_pyramid (0, 0, 0, $env->{size}, $arg[0]);

      } elsif ($cmd eq 'map_range') {
         # map range of destionation buffer
         map_range ($arg[0], $arg[1], $arg[2], $arg[3]);

      } elsif ($cmd eq 'show_region_sectors') {
         my %sectors;

         my $wg = JSON->new->relaxed->decode (_get_file ("res/world_gen.json"));
         for my $type (keys %{$wg->{sector_types}}) {
            my $s = $wg->{sector_types}->{$type};
            my $r = $s->{region_range};
            $sectors{$type} = count_in_range (@$r);
         }

         my $acc = 0;
         for (sort { $sectors{$b} <=> $sectors{$a} } keys %sectors) {
            my $p = $sectors{$_} / (100 ** 2);
            $acc += $p;
            printf "%2s: %7d (%5.2f%% acc %5.2f%%)\n", $_, $sectors{$_}, $p, $acc;
         }

      } elsif ($cmd eq 'show_range_region_sector') {
         my ($type) = @arg;
         my $wg = JSON->new->relaxed->decode (_get_file ("res/world_gen.json"));
         my $s = $wg->{sector_types}->{$type};
         my $r = $s->{region_range};
         unless ($r) {
            warn "No region range for sector type '$type' found!\n";
         }
         show_map_range (@$r);

      } elsif ($cmd eq 'show_range_sector_type') {
         my ($type, $range_offs) = @arg;
         my $wg = JSON->new->relaxed->decode (_get_file ("res/world_gen.json"));
         my $s = $wg->{sector_types}->{$type};
         my $r = $s->{ranges};
         unless ($r) {
            warn "No ranges for sector type '$type' found!\n";
         }
         show_map_range ($r->[$range_offs * 3], $r->[($range_offs * 3) + 1]);

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
