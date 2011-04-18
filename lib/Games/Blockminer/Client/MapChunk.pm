package Games::Blockminer::Client::MapChunk;
use common::sense;

=head1 NAME

Games::Blockminer::Client::MapChunk - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

A chunk of the Blockminer world.

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer::Client::MapChunk->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   return $self
}

sub update_visibility {
   # find out which blocks are possibly visible by defining
   # the outer "hull" of the chunk.
   #
   # TODO: find out how to do this iteratively if new chunks
   #       are "joining"
   #       Just reevaluate this, taking into account the adjacent chunks.
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

