package Games::Blockminer3D;
use common::sense;

our $VERSION = '0.01';

#d#require DynaLoader;
#d#our @ISA = qw(DynaLoader);
#d#
#d#sub dl_load_flags { $^O eq 'darwin' ? 0x00 : 0x01 }
#d#
#d#Games::Blockminer3D->bootstrap ($VERSION);

=head1 NAME

Games::Blockminer3D - 3D block building game written in Perl

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   return $self
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
