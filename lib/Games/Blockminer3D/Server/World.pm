package Games::Blockminer3D::Server::World;
use common::sense;
use Games::Blockminer3D::Vector;
use Games::Blockminer3D;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   world_init
   world_pos2id
   world_pos2chnkpos
   world_mutate_at
/;


=head1 NAME

Games::Blockminer3D::Server::World - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

our $CHNKSIZE = 12;

sub world_init {
   Games::Blockminer3D::World::init ($_[0]);

   my $chnk = [0,0,0];
   Games::Blockminer3D::World::query_setup (
      $chnk->[0] - 3,
      $chnk->[1] - 3,
      $chnk->[2] - 3,
      $chnk->[0] + 3,
      $chnk->[1] + 3,
      $chnk->[2] + 3
   );
   Games::Blockminer3D::World::query_load_chunks ();

   my $center = [12 * 3, 12 * 3, 12 * 3];

   my @types = (2..8);
   for my $x (0..(12 * 6 - 1)) {
      for my $y (0..(12 * 6 - 1)) {
         for my $z (0..(12 * 6 - 1)) {

            my $cur = [$x, $y, $z];
            my $l = vlength (vsub ($cur, $center));
            if ($x == 36 || $y == 36 || $z == 36 || ($l > 20 && $l < 21)) {
               my $t = [13, int rand (16)];
               Games::Blockminer3D::World::query_set_at (
                  $x, $y, $z, $t
               );
            } else {
               Games::Blockminer3D::World::query_set_at (
                  $x, $y, $z,
                  [0,int rand (16)]
               );
            }
         }
      }
   }

   Games::Blockminer3D::World::query_desetup ();
}

sub world_pos2id {
   my ($pos) = @_;
   join ",", @{vfloor ($pos)};
}

sub world_pos2chnkpos {
   vfloor (vsdiv ($_[0], $CHNKSIZE))
}

sub world_mutate_at {
   my ($pos, $cb) = @_;
   my ($chnk) = world_pos2chnkpos ($pos);

   Games::Blockminer3D::World::query_setup (
      $chnk->[0],
      $chnk->[1],
      $chnk->[2],
      $chnk->[0],
      $chnk->[1],
      $chnk->[2]
   );
   Games::Blockminer3D::World::query_load_chunks ();

   my $b = Games::Blockminer3D::World::at (@$pos);
   if ($cb->($b)) {
      my $relpos = vfloor (vsubd ($pos,
         $chnk->[0] * $CHNKSIZE,
         $chnk->[1] * $CHNKSIZE,
         $chnk->[2] * $CHNKSIZE));

      Games::Blockminer3D::World::query_set_at (@$relpos, $b);
   }

   Games::Blockminer3D::World::query_desetup ();
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

