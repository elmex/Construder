package Games::Blockminer3D::Server;
use common::sense;
use AnyEvent;
use AnyEvent::Socket;
use JSON;

use Games::Blockminer3D::Protocol;
use Games::Blockminer3D::Server::Resources;
use Games::Blockminer3D::Server::Player;

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
      my $hdl = AnyEvent::Handle->new (
         fh => $fh,
         on_error => sub {
            my ($hdl, $fatal, $msg) = @_;
            $hdl->destroy;
            $self->client_disconnected ($cid, "error: $msg");
         },
      );
      $self->{clients}->{$cid} = $hdl;
      $self->client_connected ($cid);
      $self->handle_protocol ($cid);
   };
}

sub handle_protocol {
   my ($self, $cid) = @_;

   $self->{clients}->{$cid}->push_read (packstring => "N", sub {
      my ($handle, $string) = @_;
      $self->handle_packet ($cid, data2packet ($string));
      $self->handle_protocol ($cid);
   }) if $self->{clients}->{$cid};
}

sub send_client {
   my ($self, $cid, $hdr, $body) = @_;
   $self->{clients}->{$cid}->push_write (packstring => "N", packet2data ($hdr, $body));
   warn "srv($cid)> $hdr->{cmd}\n";
}

sub client_disconnected : event_cb {
   my ($self, $cid) = @_;
   delete $self->{players}->{$cid};
   delete $self->{player_guards}->{$cid};
   delete $self->{clients}->{$cid};
}

sub client_connected : event_cb {
   my ($self, $cid) = @_;
}

sub handle_packet : event_cb {
   my ($self, $cid, $hdr, $body) = @_;

   warn "srv($cid)< $hdr->{cmd}\n";

   if ($hdr->{cmd} eq 'hello') {
      $self->send_client ($cid,
         { cmd => "hello", version => "Games::Blockminer3D::Server 0.1" });

   } elsif ($hdr->{cmd} eq 'enter') {
      my $pl = $self->{players}->{$cid}
         = Games::Blockminer3D::Server::Player->new (cid => $cid);

      $self->{player_guards}->{$cid} = $pl->reg_cb (send_client => sub {
         my ($pl, $hdr, $body) = @_;
         $self->send_client ($cid, $hdr, $body);
      });

      $pl->init;

   } elsif ($hdr->{cmd} eq 'ui_response') {
      $self->{players}->{$cid}->ui_res ($hdr->{ui}, $hdr->{ui_command}, $hdr->{arg});
   } elsif ($hdr->{cmd} eq 'player_pos') {
      $self->{players}->{$cid}->update_pos ($hdr->{pos});
   }
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

