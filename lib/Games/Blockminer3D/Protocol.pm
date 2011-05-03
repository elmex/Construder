package Games::Blockminer3D::Protocol;
use common::sense;
require Exporter;
use POSIX qw/floor/;
our @EXPORT = qw/
   packet2data
   data2packet
/;

=head1 NAME

Games::Blockminer3D::Protocol - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

sub packet2data {
   my ($header, $body) = @_;
   my $hdr_data = JSON->new->encode ($header);
   my $data = (pack "N", length $hdr_data) . $hdr_data . $body;
   (pack "N", length $data) . $data
}

sub data2packet : event_cb {
   my ($buffer) = @_;

   my @packets;
   while (length ($buffer) > 4) {
      my $len = unpack "N", substr $buffer, 0, 4;
      if (length ($buffer) >= ($len + 4)) {
         substr $buffer, 0, 4, '';
         my $packet = substr $buffer, 0, $len, '';
         my $hdr_len  = unpack "N", substr ($packet, 0, 4, '');
         my $hdr      = substr $packet, 0, $hdr_len, '';
         my $body     = $packet;
         push @packets, [$hdr, $body];
      }
   }

   @packets
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

