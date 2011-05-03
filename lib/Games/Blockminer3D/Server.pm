package Games::Blockminer3D::Server;
use common::sense;
use AnyEvent;
use AnyEvent::Socket;
use JSON;

use Games::Blockminer3D::Server::Resources;

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

   $self->{port} ||= 9364;

   return $self
}

sub init {
   my ($self) = @_;

   $self->{res} = Games::Blockminer3D::Server::Resources->new;
   $self->{res}->load_objects;
}

sub listen {
   my ($self) = @_;

   tcp_server undef, $self->{port}, sub {
      my ($fh, $h, $p) = @_;
      $self->{clids}++;
      my $cid = "$h:$p:$self->{clids}";
      $self->{clients}->{$cid} = [$fh];
      my $hdl = AnyEvent::Handle->new (
         fh => $fh,
         on_error => sub {
            my ($hdl, $fatal, $msg) = @_;
            $hdl->destroy;
            $self->client_disconnected ($cid, "error: $msg");
         },
      );
      $self->client_connected ($cid);
   };
}

sub handle_protocol {
   my ($self, $cid) = @_;

   $self->{clients}->{$cid}->push_read (packstring => "N", sub {
      my ($handle, $string) = @_;
      $self->handle_packet ($cid, data2packet ($string));
      $self->handle_protocol;
   });
}

sub send_client {
   my ($self, $cid, $hdr, $body) = @_;
   $self->{clients}->{$cid}->push_write (packstring => "N", packet2data ($hdr, $body));
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

sub handle_packet : event_cb {
   my ($self, $cid, $hdr, $body) = @_;
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

