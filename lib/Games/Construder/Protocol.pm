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
package Games::Construder::Protocol;
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

Games::Construder::Protocol - Client-Server Protocol Utility Functions

=over 4

=cut

my $JS = JSON->new;

sub packet2data {
   my ($header, $body) = @_;
   my $hdr_data = $JS->encode ($header);
   $body = $$body if ref $body;
   my $data = (pack "N", length $hdr_data) . $hdr_data . $body;
   $data
}

sub data2packet {
   my ($data) = @_;
   my $hdr_len  = unpack "N", substr ($data, 0, 4, '');
   my $hdr      = substr $data, 0, $hdr_len, '';
   my $body     = $data;
   $hdr = $JS->decode ($hdr);
   ($hdr, $body)
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License.

=cut

1;

