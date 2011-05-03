package Games::Blockminer3D::Client;
use common::sense;
use Games::Blockminer3D::Client::Frontend;
use Games::Blockminer3D::Client::MapChunk;
use Games::Blockminer3D::Client::World;
use Games::Blockminer3D::Server;
use Games::Blockminer3D::Protocol;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Math::VectorReal;
use Benchmark qw/:all/;

use base qw/Object::Event/;

=head1 NAME

Games::Blockminer3D::Client - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Client->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;
   #d# my $sect = Games::Blockminer3D::Server::Sector->new;
   #d# timethese (20, { test => sub {
   #d#    $sect->mk_random;
   #d# }});
   #d#    my $chunk = $sect->get_chunk (1, 1, 1);
   #d# exit;

   $self->init_object_events;

   $self->{server} = Games::Blockminer3D::Server->new;
   $self->{server}->init;
   $self->{server}->listen;

   $self->{front} = Games::Blockminer3D::Client::Frontend->new;

   my $chnk = Games::Blockminer3D::Client::MapChunk->new;
   $chnk->cube_fill;
   world_set_chunk (0, 0, 0, $chnk);

   $self->{front}->reg_cb (update_player_pos => sub {
      $self->send_server ({ cmd => "player_pos", pos => $_[1] });
   });

   $self->connect (localhost => 9364);

   return $self
}

sub start {
   my ($self) = @_;

   my $c = AnyEvent->condvar;

   $c->recv;
}

sub msgbox {
   my ($self, $msg, $cb) = @_;

   $self->{front}->activate_ui (cl_msgbox => {
      window => {
         extents => [ 'center', 'center', 0.9, 0.1 ],
         color => "#000000",
         alpha => 1,
      },
      elements => [
         {
            type => "text",
            extents => [0, 0, 1, 0.6],
            align => "center",
            font => 'normal',
            color => "#ffffff",
            text => $msg
         },
         {
            type => "text",
            extents => [0, 0.6, 1, 0.4],
            align => "center",
            font => 'small',
            color => "#888888",
            text => "press ESC to hide",
         }
      ]
   });
}

sub connect {
   my ($self, $host, $port) = @_;

   tcp_connect $host, $port, sub {
      my ($fh) = @_
         or die "connect failed: $!\n";

      my $hdl = AnyEvent::Handle->new (
         fh => $fh,
         on_error => sub {
            my ($hdl, $fatal, $msg) = @_;
            $hdl->destroy;
            $self->disconnected;
         }
      );

      $self->{srv} = $hdl;
      $self->handle_protocol;
      $self->connected;
   };
}

sub handle_protocol {
   my ($self) = @_;

   $self->{srv}->push_read (packstring => "N", sub {
      my ($handle, $string) = @_;
      $self->handle_packet (data2packet ($string));
      $self->handle_protocol;
   });
}

sub send_server {
   my ($self, $hdr, $body) = @_;
   if ($self->{srv}) {
      $self->{srv}->push_write (packstring => "N", packet2data ($hdr, $body));
      warn "cl> $hdr->{cmd}\n";
   }
}

sub connected : event_cb {
   my ($self) = @_;
   $self->send_server ({ cmd => 'hello', version => "Games::Blockminer3D::Client 0.1" });
}

sub handle_packet : event_cb {
   my ($self, $hdr, $body) = @_;

   warn "cl< $hdr->{cmd}\n";

   if ($hdr->{cmd} eq 'hello') {
      $self->msgbox ("Connected to Server!");
      $self->send_server ({ cmd => 'enter' });

   } elsif ($hdr->{cmd} eq 'place_player') {
      $self->{front}->set_player_pos ($hdr->{pos});

   } elsif ($hdr->{cmd} eq 'activate_ui') {
      my $desc = $hdr->{desc};
      $desc->{command_cb} = sub {
         my ($cmd, $arg) = @_;
         $self->send_server ({
            cmd => 'ui_response' =>
               ui => $hdr->{ui}, ui_command => $cmd, arg => $arg
         });
      };
      $self->{front}->activate_ui ($hdr->{ui}, $desc);

   } elsif ($hdr->{cmd} eq 'deactivate_ui') {
      $self->{front}->deactivate_ui ($hdr->{ui});

   } elsif ($hdr->{cmd} eq 'texture_upload') {
      $self->{front}->{textures}->add (
         $body, [[$hdr->{txt_nr}, $hdr->{txt_uv}, $hdr->{txt_md5}]]
      );

   } elsif ($hdr->{cmd} eq 'chunk') {
      my $chnk = Games::Blockminer3D::Client::MapChunk->new;
      $chnk->data_fill ($body);
      world_set_chunk (@{$hdr->{pos}}, $chnk);
      world_change_chunk (@{$hdr->{pos}});
   }
}

sub disconnected : event_cb {
   my ($self) = @_;
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

