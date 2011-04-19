package Games::Blockminer::Client;
use common::sense;
use Games::Blockminer::Client::Frontend;
use Games::Blockminer::Client::MapChunk;
use AnyEvent;
use Math::VectorReal;

=head1 NAME

Games::Blockminer::Client - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer::Client->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->{front} = Games::Blockminer::Client::Frontend->new;

   my $chnk = Games::Blockminer::Client::MapChunk->new;
   $chnk->random_fill;

   $self->{front}->set_chunk (vector (0, 0, 0), $chnk);
   $self->{front}->change_look_lock (1);

   return $self
}

sub start {
   my ($self) = @_;

   my $c = AnyEvent->condvar;

   $c->recv;
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

