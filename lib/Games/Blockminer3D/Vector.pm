package Games::Blockminer3D::Vector;
use common::sense;
require Exporter;
use POSIX qw/floor/;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   vneg vineg
   vadd vaddd viadd viaddd
   vsub vsubd visub visubd
   vsdiv visdiv
   vsmul vismul
   vdot vdotd vcross vlength
   vnorm vinorm
   vplane
   vfloor
   vstr
/;

=head1 NAME

Games::Blockminer3D::Vector - Vector Math Utilities

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

sub vfloor { [ map { floor ($_[0][$_]) } 0..2 ] }

sub vneg   { [ map { -$_[0][$_] } 0..2 ] }
sub vineg  { $_[0][$_] -= -$_[0][$_] for 0..2 }

sub vadd   { [ map { $_[0][$_] + $_[1][$_]  } 0..2 ] }
sub vaddd  { [ map { $_[0][$_] + $_[$_ + 1] } 0..2 ] }
sub viadd  { $_[0][$_] += $_[1][$_]  for 0..2 }
sub viaddd { $_[0][$_] += $_[$_ + 1] for 0..2 }

sub vsub   { [ map { $_[0][$_] - $_[1][$_]  } 0..2 ] }
sub vsubd  { [ map { $_[0][$_] - $_[$_ + 1] } 0..2 ] }
sub visub  { $_[0][$_] -= $_[1][$_]  for 0..2 }
sub visubd { $_[0][$_] -= $_[$_ + 1] for 0..2 }

sub vsdiv  { [ map { $_[0][$_] / $_[1] } 0..2 ] }
sub visdiv { $_[0][$_] /= $_[1] for 0..2 }

sub vsmul  { [ map { $_[0][$_] * $_[1] } 0..2 ] }
sub vismul { $_[0][$_] *= $_[1] for 0..2 }

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
   sprintf "[%9.4f %9.4f %9.4f]", @{$_[0]}
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

