package Games::Blockminer3D::Server::Sector;
use common::sense;
use Games::Blockminer3D::Vector;

=head1 NAME

Games::Blockminer3D::Server::Sector - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Server::Sector->new (%args)

=cut

our $SIZE     = 60;
our $CHNKSIZE = 12;
our $CHNKS_P_SECTOR = $SIZE / $CHNKSIZE;

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   return $self
}

sub mk_random {
   my ($self) = @_;

   my $sect = "\x00" x ($SIZE ** 3);

   for my $dx (0..($SIZE - 1)) {
      for my $dy (0..($SIZE - 1)) {
         for my $dz (0..($SIZE - 1)) {
            my $offs = $dx + $dy * $SIZE + $dz * ($SIZE ** 2);
            my ($type, $light) = (int rand (128), int rand (16));
            my $blk = ($type & 0xFFF0 | $light & 0x000F);
            my $content = pack "nCC", $blk, 0, 0;
            substr $sect, $offs, 4, $content;
         }
      }
   }

   $self->{data} = $sect;
}

sub get_chunk {
   my ($self, $relchnkpos) = @_;
   my $sec_data = $self->{data};

   my $from = vsmul ($relchnkpos, $CHNKSIZE);
   my $to   = vsmul (vaddd ($relchnkpos, 1, 1, 1), $CHNKSIZE);
   my $chnk = "\x00" x (16 ** 3);

   my $blks = 0;
   for my $dx ($from->[0]..($to->[0] - 1)) {
      for my $dy ($from->[1]..($to->[1] - 1)) {
         for my $dz ($from->[2]..($to->[2] - 1)) {
            my $chnk_offs =
                ($dx - $from->[0])
                + ($dy - $from->[1]) * $CHNKSIZE
                + ($dz - $from->[2]) * ($CHNKSIZE ** 2);
            my $offs      = $dx + $dy * $SIZE + $dz * ($SIZE ** 2);
            warn "CHNK $chnk_offs | $offs | $dx, $dy, $dz ($blks)\n";
            substr $chnk, $chnk_offs, 4, (substr $sec_data, $offs, 4);
         }
      }
   }
   exit;

   $chnk
}

sub get_chunk_data_at_chnkpos {
   my ($self, $chnkpos) = @_;

   # FIXME: calculation of positions needs to be cleaned up!
   my $sector = vfloor (vsdiv ($chnkpos, $CHNKS_P_SECTOR));
   my $relchnkpos = vsub ($chnkpos, vsmul ($sector, $CHNKS_P_SECTOR));
   warn "Chunk pos (sector " . vstr ($sector) .  " ) "
        . vstr ($chnkpos) . " =>rel: " . vstr ($relchnkpos) . "\n";

   $self->get_chunk ($relchnkpos)
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

