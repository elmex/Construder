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
   world_chnkpos2secpos
   world_secpos2chnkpos
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
our $CHNKS_P_SEC = 5;

sub world_init {
   Games::Blockminer3D::World::init ($_[0]);

}

sub world_pos2id {
   my ($pos) = @_;
   join "x", map { $_ < 0 ? "N" . abs ($_) : $_ } @{vfloor ($pos)};
}

sub world_pos2chnkpos {
   vfloor (vsdiv ($_[0], $CHNKSIZE))
}

sub world_chnkpos2secpos {
   my $unadj_sec = vfloor (vsdiv ($_[0], $CHNKS_P_SEC));
   my $offs = ($unadj_sec->[1] % 3);
   my $nchnk = vaddd ($_[0], $offs, 0, $offs);
   vfloor (vsdiv ($nchnk, $CHNKS_P_SEC))
}

sub world_secpos2chnkpos {
   my $chnk = vsmul ($_[0], $CHNKS_P_SEC);
   vsubd ($chnk, $_[0]->[1] % 3, 0, $_[0]->[1] % 3)
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

