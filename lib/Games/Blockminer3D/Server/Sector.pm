package Games::Blockminer3D::Server::Sector;
use common::sense;
use AnyEvent::Util;
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

sub secset {
   my ($rdata, $pos, $cont) = @_;
   my $offs = $pos->[0] + $pos->[1] * $SIZE + $pos->[2] * ($SIZE ** 2);
   my ($type, $light, $m, $a) = @$cont;#(int rand (10) > 5 ? 0 : 1, int rand (16));
   my $blk = (($type << 4) & 0xFFF0)| ($light & 0x000F);
   my $content = pack "nCC", $blk, $m, $a;
   substr $$rdata, $offs * 4, 4, $content;
}

sub mk_random {
   my ($self) = @_;

   warn "SECTOR RANDOM!\n";

   my $sect = "\x00" x (($SIZE ** 3) * 4);

   #d#for my $cx (0..4) {
   #d#   for my $cy (0..4) {
   #d#      for my $cz (0..4) {
   #d#         my $c = $CHNKSIZE / 2;
   #d#         my $p = [
   #d#            $cx * $CHNKSIZE + ($CHNKSIZE / 2),
   #d#            $cy * $CHNKSIZE + ($CHNKSIZE / 2),
   #d#            $cz * $CHNKSIZE + ($CHNKSIZE / 2)
   #d#         ];
   #d#         secset (\$sect, $p, [1, 16]);
   #d#         secset (\$sect, vaddd ($p, 0, 0, 1), [1, 16]);
   #d#         secset (\$sect, vaddd ($p, 1, 0, 0), [1, 16]);
   #d#         secset (\$sect, vaddd ($p, 1, 0, 1), [1, 16]);
   #d#         warn "SEt AT " . vstr ($p) . "\n";
   #d#      }
   #d#   }
   #d#}
   srand (1);

   for my $dx (0..($SIZE - 1)) {
      for my $dy (0..($SIZE - 1)) {
         for my $dz (0..($SIZE - 1)) {
            if (rand (100) > 80) {
               my $offs = $dx + $dy * $SIZE + $dz * ($SIZE ** 2);
               secset (\$sect, [$dx, $dy, $dz], [7, int rand (16)]);
            }
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
   my $chnk = "\x00" x ((16 ** 3) * 4);

   my $blks = 0;
   for my $dx ($from->[0]..($to->[0] - 1)) {
      for my $dy ($from->[1]..($to->[1] - 1)) {
         for my $dz ($from->[2]..($to->[2] - 1)) {
            my $chnk_offs =
                ($dx - $from->[0])
                + ($dy - $from->[1]) * $CHNKSIZE
                + ($dz - $from->[2]) * ($CHNKSIZE ** 2);
            my $offs      = $dx + $dy * $SIZE + $dz * ($SIZE ** 2);
            #d# warn "CHNK $chnk_offs | $offs | $dx, $dy, $dz ($blks)\n";
            #d# warn "LEN" . length ($sec_data) . "\n";
            substr $chnk, $chnk_offs * 4, 4, (substr $sec_data, $offs * 4, 4);
         }
      }
   }

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

