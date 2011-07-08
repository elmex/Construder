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
package Games::Construder::Vector;
use common::sense;
require Exporter;
use POSIX qw/floor/;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   vneg vineg
   vadd vaddd viadd viaddd vsadd visadd
   vsub vsubd visub visubd
   vsdiv visdiv
   vsmod vismod
   vsmul vismul
   vdot vdotd vcross vlength
   vnorm vinorm
   vplane
   vfloor vifloor
   vstr
   vrand

   vadd_2d vaddd_2d viadd_2d viaddd_2d
   vsub_2d vsubd_2d visub_2d visubd_2d
   vsdiv_2d visdiv_2d
   vsmul_2d vismul_2d
   vdot_2d vdotd_2d vlength_2d
   vnorm_2d vinorm_2d

   vaccum

   vcompres
/;

=head1 NAME

Games::Construder::Vector - Vector Math Utilities

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

sub vaccum {
   defined $_[0]
      ? vadd ($_[0], $_[1])
      : [@{$_[1]}]
}

sub vfloor  { [ map { floor ($_[0][$_])       } 0..2 ] }
sub vifloor { $_[0][$_] = floor ($_[0][$_]) for 0..2 }

sub vneg   { [ map { -$_[0][$_] }        0..2 ] }
sub vineg  { $_[0][$_] -= -$_[0][$_] for 0..2 }

sub vadd   { [ $_[0][0] + $_[1][0], $_[0][1] + $_[1][1], $_[0][2] + $_[1][2]] }
sub vsadd  { [ map { $_[0][$_] + $_[1]      } 0..2 ] }
sub vaddd  { [ $_[0][0] + $_[1], $_[0][1] + $_[2], $_[0][2] + $_[3] ] }
sub viadd  { $_[0][$_] += $_[1][$_]       for 0..2 }
sub visadd { $_[0][$_] += $_[1]           for 0..2 }
sub viaddd { $_[0][$_] += $_[$_ + 1]      for 0..2 }

sub vsub   { [ map { $_[0][$_] - $_[1][$_]  } 0..2 ] }
sub vsubd  { [ map { $_[0][$_] - $_[$_ + 1] } 0..2 ] }
sub visub  { $_[0][$_] -= $_[1][$_]       for 0..2 }
sub visubd { $_[0][$_] -= $_[$_ + 1]      for 0..2 }

sub vsdiv  { [ map { $_[0][$_] / $_[1] } 0..2 ] }
sub visdiv { $_[0][$_] /= $_[1]      for 0..2 }
sub vsmod  { [ map { $_[0][$_] % $_[1] } 0..2 ] }
sub vismod { $_[0][$_] %= $_[1]      for 0..2 }

sub vsmul  { [ map { $_[0][$_] * $_[1] } 0..2 ] }
sub vismul { $_[0][$_] *= $_[1]      for 0..2 }

sub vdot {
     $_[0][0] * $_[1][0]
   + $_[0][1] * $_[1][1]
   + $_[0][2] * $_[1][2]
}

sub vdotd {
     $_[0][0] * $_[1]
   + $_[0][1] * $_[2]
   + $_[0][2] * $_[3]
}

sub vcross {
   [
      $_[0][1] * $_[1][2] - $_[0][2] * $_[1][1],
      $_[0][2] * $_[1][0] - $_[0][0] * $_[1][2],
      $_[0][0] * $_[1][1] - $_[0][1] * $_[1][0],
   ]
}

sub vlength { sqrt (vdot ($_[0], $_[0])) }

sub vnorm  { vsdiv ($_[0] , defined $_[1] ? $_[1] : vlength ($_[0])) }
sub vinorm { visdiv ($_[0], defined $_[1] ? $_[1] : vlength ($_[0])) }

sub vplane {
   my $n = vnorm (vcross (vsub ($_[1], $_[0]), vsub ($_[2], $_[1])));
   ($n, vdot ($_[0], $n))
}

sub vstr {
   @{$_[0]} > 2
      ? sprintf "[%9.4f %9.4f %9.4f]", @{$_[0]}
      : sprintf "[%9.4f %9.4f]", @{$_[0]}
}

sub vrand {
   [(rand () * 2) - 1,
    (rand () * 2) - 1,
    (rand () * 2) - 1]
}

# 2D Vector math:
sub vfloor_2d { [ map { floor ($_[0][$_]) } 0..1 ] }

sub vneg_2d   { [ map { -$_[0][$_] }        0..1 ] }
sub vineg_2d  { $_[0][$_] -= -$_[0][$_] for 0..1 }

sub vadd_2d   { [ map { $_[0][$_] + $_[1][$_]  } 0..1 ] }
sub vaddd_2d  { [ map { $_[0][$_] + $_[$_ + 1] } 0..1 ] }
sub viadd_2d  { $_[0][$_] += $_[1][$_]       for 0..1 }
sub viaddd_2d { $_[0][$_] += $_[$_ + 1]      for 0..1 }

sub vsub_2d   { [ map { $_[0][$_] - $_[1][$_]  } 0..1 ] }
sub vsubd_2d  { [ map { $_[0][$_] - $_[$_ + 1] } 0..1 ] }
sub visub_2d  { $_[0][$_] -= $_[1][$_]       for 0..1 }
sub visubd_2d { $_[0][$_] -= $_[$_ + 1]      for 0..1 }

sub vsdiv_2d  { [ map { $_[0][$_] / $_[1] } 0..1 ] }
sub visdiv_2d { $_[0][$_] /= $_[1]      for 0..1 }

sub vsmul_2d  { [ map { $_[0][$_] * $_[1] } 0..1 ] }
sub vismul_2d { $_[0][$_] *= $_[1]      for 0..1 }

sub vdot_2d {
     $_[0][0] * $_[1][0]
   + $_[0][1] * $_[1][1]
}

sub vdotd_2d {
     $_[0][0] * $_[1] + $_[0][1] * $_[2]
}

sub vlength_2d { sqrt (vdot_2d ($_[0], $_[0])) }

sub vnorm_2d  { vsdiv_2d ($_[0] , defined $_[1] ? $_[1] : vlength_2d ($_[0])) }
sub vinorm_2d { visdiv_2d ($_[0], defined $_[1] ? $_[1] : vlength_2d ($_[0])) }

sub vcompres {
   my ($p) = @_;
   [
      map {
         (sprintf "%0.4f", $_) * 1
      } @$p
   ]
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License.

=cut

1;

