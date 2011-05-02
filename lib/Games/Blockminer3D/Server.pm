package Games::Blockminer3D::Server;
use common::sense;
use AnyEvent;
use AnyEvent::Socket;
use JSON;

use base qw/Object::Event/;

=head1 NAME

Games::Blockminer3D::Server - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Server->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;

   return $self
}

sub init {
}

sub listen {
}

sub inject_packet { # inject packet and simulate networking :)
   my ($self, $client_id, $header, $body) = @_;
   my $hdr_data = JSON->new->encode ($header);
   my $data = (pack "N", length $hdr_data) . $hdr_data . $body;
   my $t; $t = AE::timer 0, 0, sub {
      $self->handle_data ($client_id, $data);
      undef $t;
   };
}

sub handle_data : event_cb {
   my ($self, $client_id, $data) = @_;
   my $hdr_len  = unpack "N", substr ($data, 0, 4, '');
   my $hdr      = substr $data, 0, $hdr_len, '';
   my $body     = $data;
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

