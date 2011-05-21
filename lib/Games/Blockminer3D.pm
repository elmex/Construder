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
   set0 => 5,
   set1 => 6,
);

sub draw_commands {
   my ($str, $env) = @_;

   for (split /\s*\r?\n\s*/s, $str) {
      s/^\s+//;
      if (/^mode (\S+)/) {
         set_op ($OPS{$1});

      } elsif (/^swap/) {
         swap ();

      } elsif (/^src_range (\d+(?:\.\d+)?) (\d+(?:\.\d+)?)/) {
         src_range ($1, $2);

      } elsif (/^fill (\d+(?:\.\d+)?)?/) {
         if ($1 ne '') {
            val ($1);
         } else {
            src ();
         }

      } elsif (/^spheres (\d+) (\d+(?:\.\d+)?)/) {
         # spheres <recursion-cnt> <src blend & gradient direction>
         sphere_subdiv (0, 0, 0, $env->{size}, $2, $1);

      } elsif (/^sphere_surfaces (\d+) (\d+(?:\.\d+)?)/) {
         # sphere_surfaces <recursion-cnt> <surface thickness>
         sphere_surface_subdiv (0, 0, 0, $env->{size}, $2, $1);

      } elsif (/^noise (\d+) (\d+(?:\.\d+)?) (\d+(?:\.\d+)?)/) {
         # noise <octaves> <scale factor> <persistence>
         fill_simple_noise_octaves ($env->{seed}, $1, $2, $3);

      } elsif (/^menger_sponge (\d+)/) { # <lvl>
         menger_sponge_box (0, 0, 0, $env->{size}, $1);

      } elsif (/^cantor_dust (\d+)/) { # <lvl>
         cantor_dust_box (0, 0, 0, $env->{size}, $1);

      } elsif (/^map_range (\d+(?:\.\d+)?) (\d+(?:\.\d+)?) (\d+(?:\.\d+)?) (\d+(?:\.\d+)?)/) {
         map_range ($1, $2, $3, $4);

      } elsif (/^#/) {
         # comment

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
