package Games::Blockminer3D::Vector;
use common::sense;
require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/vlength vneg vnegd vadd vaddd vsub vsubd vsdiv vsmul vdot vdotd vcross vlength vnorm vplane/;

=head1 NAME

Games::Blockminer3D::Vector - Vector Math Utilities

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

sub vneg { [ map { $_[0][$_] = -$_[0][$_] } 0..2 ] }

sub vnegd { [ map { $_[0][$_] = -$_[$_ + 1] } 0..2 ] }

sub vadd { [ map { $_[0][$_] + $_[1][$_] } 0..2 ] }

sub vaddd { [ map { $_[0][$_] + $_[$_ + 1] } 0..2 ] }

sub vsub { [ map { $_[0][$_] - $_[1][$_] } 0..2 ] }

sub vsubd { [ map { $_[0][$_] - $_[$_ + 1] } 0..2 ] }

sub vsdiv { [ map { $_[0][$_] / $_[1] } 0..2 ] }

sub vsmul { [ map { $_[0][$_] * $_[1] } 0..2 ] }

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

sub vnorm { vsdiv ($_[0], vlength ($_[0])) }

sub vplane {
   my $n = vnorm (vcross (vsub ($_[1], $_[0]), vsub ($_[2], $_[1])));
   ($n, vdot ($_[0], $n))
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

