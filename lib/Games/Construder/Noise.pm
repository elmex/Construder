package Games::Construder::Noise;
use common::sense;

=head1 NAME

Games::Construder::Noise - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

sub cos_intrp {
   my ($a, $b, $x) = @_;
   my $ft = $x * 3.1415927;
   my $f = (1 - cos ($ft)) * 0.5;
   $a * (1 - $f) + $b * $f
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

