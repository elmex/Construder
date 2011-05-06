package Games::Blockminer3D::Protocol;
use common::sense;
use JSON;

require Exporter;
use POSIX qw/floor/;
our @ISA = qw/Exporter/;
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
   $data
}

sub data2packet {
   my ($data) = @_;
   my $hdr_len  = unpack "N", substr ($data, 0, 4, '');
   my $hdr      = substr $data, 0, $hdr_len, '';
   my $body     = $data;
   $hdr = JSON->new->relaxed->decode ($hdr);
   ($hdr, $body)
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

