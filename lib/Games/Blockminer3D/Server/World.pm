package Games::Blockminer3D::Server::World;
use common::sense;
use Games::Blockminer3D::Vector;
use Games::Blockminer3D::Server::Sector;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   world_pos2id
   world_sector_at
   world_pos2secref
   world_pos2chnkpos
   world_get_chunk_data
/;


=head1 NAME

Games::Blockminer3D::Server::World - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

my %SECTORS;

sub world_pos2id {
   my ($pos) = @_;
   join ",", @{vfloor ($pos)};
}

sub world_pos2chnkpos {
   vfloor (vsdiv ($_[0], $Games::Blockminer3D::Server::Sector::CHNKSIZE))
}

sub world_pos2secref {
   my ($pos) = @_;
   my $id = world_pos2id ($pos);
   my $s = \$SECTORS{$id};
   warn "SECTOR ID $id: $$s\n";
   $s
}

sub world_sector_at {
   my ($chnkpos, $cb) = @_;

   my $secpos =
      vfloor (
         vsdiv ($chnkpos, $Games::Blockminer3D::Server::Sector::CHNKS_P_SECTOR));
   my $sec = world_pos2secref ($secpos);

   if (defined $$sec) {
      $cb->($$sec);

   } else {
      $$sec = Games::Blockminer3D::Server::Sector->new;
      $$sec->mk_random;
      $cb->($$sec);
   }
}

sub world_get_chunk_data {
   my ($chnkpos, $cb) = @_;

   world_sector_at ($chnkpos, sub {
      my ($sector) = @_;
      my $data = $sector->get_chunk_data_at_chnkpos ($chnkpos);
      $cb->($data);
   });
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

