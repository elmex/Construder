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
   world_mutate_at
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

sub world_mutate_at {
   my ($pos, $cb) = @_;
   my ($secpos) =
      vfloor (
        vsdiv ($pos, $Games::Blockminer3D::Server::Sector::SIZE));

   my ($relpos) =
      vfloor (vsub ($pos, vsmul ($secpos, $Games::Blockminer3D::Server::Sector::SIZE)));
   my $sec = world_pos2secref ($secpos);
   if ($$sec) {
      $$sec->mutate_at ($relpos, $cb);
   }
}

sub load_sector {
   my ($secref, $pos, $cb) = @_;

   if (defined $$secref) {
      $cb->($$secref);

   } else {
      $$secref = Games::Blockminer3D::Server::Sector->new;
         my $dat;
         if ($pos->[0] == 0 && $pos->[1] == 0 && $pos->[2] == 0) {
            $dat = $$secref->mk_construct;
         } else {
            $dat = $$secref->mk_random;
         }
         $$secref->{data} = $dat;
         $cb->($$secref);
         return;

      #d# AnyEvent::Util::fork_call {
      #d#    my $dat = $$secref->mk_random;
      #d#    warn "DONE: ".length ($dat)."\n";
      #d#    $dat
      #d# } sub {
      #d#    my ($data) = @_;
      #d#    $$secref->{data} = $data;
      #d#    $cb->($$secref);
      #d# };
   }

}

sub world_sector_at {
   my ($chnkpos, $cb) = @_;

   my $secpos =
      vfloor (
         vsdiv ($chnkpos, $Games::Blockminer3D::Server::Sector::CHNKS_P_SECTOR));
   my $sec = world_pos2secref ($secpos);

   load_sector ($sec, $secpos, $cb);
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

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

