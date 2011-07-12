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
package Games::Construder;
use JSON;
use common::sense;
use Time::HiRes qw/time/;
require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   ctr_prof
/;

our $VERSION = '0.92';

use XSLoader;
XSLoader::load "Games::Construder", $Games::Construder::VERSION;

=head1 NAME

Games::Construder - A 3D game written in Perl, which is actually playable!

=head1 SYNOPSIS

   Starting the server:

   user@host ~# construder_server

   Starting the client:

   user@host ~# construder_client

=head1 DESCRIPTION

This is the source code documentation for the game called "Construder".

If you search for information on how to actually play it please look at
the official website for introduction videos:

L<http://ue.o---o.eu/>

You can also find other interesting information there, such as screenshots,
the motivation of writing this game or B<where to go with questions and/or bug
reports.>

=head1 PACKAGES

This specific module file provides the XS bindings and also some utility
functions that are used in many places in the game.

=over 4

=cut

our $PROF_DEBUG = 0;

sub ctr_prof {
   my ($name, $sub) = @_;
   if (!$PROF_DEBUG) {
      $sub->();
      return;
   }
   my $t1 = time;
   $sub->();
   printf "ctr_prof[%-20s] %0.4f\n", $name, time - $t1;
}

package Games::Construder::Util;

sub visible_chunks_at {
   my ($pos, $rad) = @_;

   my $chnks =
      Games::Construder::Math::calc_visible_chunks_at (@$pos, $rad);
   my @o;
   for (my $i = 0; $i < @$chnks; $i += 3) {
      push @o, [$chnks->[$i], $chnks->[$i + 1], $chnks->[$i + 2]];
   }
   #d#warn "visible chunks: " . scalar (@o) . "\n";
   return @o
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

      } elsif ($cmd eq 'hist_equalize') {
         # hist_equalize <number of buckets> <range from> <range to>
         histogram_equalize ($arg[0] || 1, $arg[1], $arg[2]);

      } elsif ($cmd eq 'coords') {
         ($env->{coords_x}, $env->{coords_y}, $env->{coords_z},
          $env->{coords_sx}, $env->{coords_sy}, $env->{coords_sz}) = (@arg);

      } elsif ($cmd eq 'mandelbox') {
         # mandelbox <s> <r> <f> <it> <coordscale>
         mandel_box ($env->{coords_x}, $env->{coords_y}, $env->{coords_z}, $env->{coords_sx}, $env->{coords_sy}, $env->{coords_sz}, $arg[0], $arg[1], $arg[2], $arg[3], $arg[4]);

      } elsif ($cmd eq 'show_region_sectors') {
         # show_region_sectors
         my %sectors;

         my $wg = JSON->new->relaxed->decode (_get_file ("res/world_gen.json"));
         for my $type (keys %{$wg->{sector_types}}) {
            my $s = $wg->{sector_types}->{$type};
            my $r = $s->{region_range};
            $sectors{$type} = [count_in_range (@$r), $r];
         }

         my $acc = 0;
         for (sort { $sectors{$b}->[0] <=> $sectors{$a}->[0] } keys %sectors) {
            my $p = $sectors{$_}->[0] / (100 ** 2);
            $acc += $p;
            printf "%2s: %7d (%5.2f%% acc %5.2f%%) [%5.4f,%5.4f)\n",
                   $_, $sectors{$_}->[0], $p, $acc, @{$sectors{$_}->[1]};
         }

      } elsif ($cmd eq 'show_range_region_sector') {
         # show_range_region_sector <sector type>
         my ($type) = @arg;
         my $wg = JSON->new->relaxed->decode (_get_file ("res/world_gen.json"));
         my $s = $wg->{sector_types}->{$type};
         my $r = $s->{region_range};
         unless ($r) {
            warn "No region range for sector type '$type' found!\n";
         }
         show_map_range (@$r);

      } elsif ($cmd eq 'show_range_sector_type') {
         # show_range_region_sector <sector type> <idx in range array>
         my ($type, $range_idx) = @arg;
         my $wg = JSON->new->relaxed->decode (_get_file ("res/world_gen.json"));
         my $s = $wg->{sector_types}->{$type};
         my $r = $s->{ranges};
         unless ($r) {
            warn "No ranges for sector type '$type' found!\n";
         }
         show_map_range ($r->[$range_idx * 3], $r->[($range_idx * 3) + 1]);

      } else {
         warn "unknown draw command: $_\n";
      }
   }
}

package Games::Construder::Debug;
use AnyEvent::Debug;

our $SHELL;

sub init {
   my ($name) = @_;

   return unless $ENV{PERL_GAMES_CONSTRUDER_DEBUG};

   $Data::Dumper::Indent = 2;

   my $sock = "/tmp/construder_shell_$name";

   $SHELL = AnyEvent::Debug::shell "unix/", $sock;
   if ($SHELL) {
      warn "started shell at $sock, use with: 'socat readline $sock'\n";
   }
}

package AnyEvent::Debug::shell;
use common::sense;
use Data::Dumper;

sub d {
   my ($d) = @_;
   Dumper ($d)
}

sub wf {
   my ($name, $data) = @_;
   open my $fh, ">", "/tmp/$name.debug"
      or die "Couldn't open /tmp/$name.debug: $!\n";
   binmode $fh;
   print $fh $data;
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

L<http://www.deliantra.net/> - Another game written with a lot of Perl, facilitating C<Coro>, C<IO::AIO>, C<AnyEvent>, C<JSON> and many other Perl modules.

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License.

=cut

1;
