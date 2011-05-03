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

   $self->{server} = Games::Blockminer3D::Server->new;
   $self->{server}->init;

   $self->{front} = Games::Blockminer3D::Client::Frontend->new;

   for my $x (-1..1) {
      for my $y (-1..1) {
         for my $z (-1..1) {
            my $chnk = Games::Blockminer3D::Client::MapChunk->new;
            $chnk->cube_fill;
            world_set_chunk ($x, $y, $z, $chnk);
         }
      }
   }
#   $chnk->random_fill;

 #  $self->{front}->change_look_lock (1);
 #  $self->{front}->compile_scene;

   $self->{front}->activate_ui ("test", { });

   return $self
}

sub start {
   my ($self) = @_;

   my $c = AnyEvent->condvar;

   $c->recv;
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
      $self->connected;
   };
}

sub handle_protocol {
   my ($self) = @_;

   $self->{srv}->push_read (packstring => "N", sub {
      my ($handle, $string) = @_;
      $self->handle_packet ($cid, data2packet ($string));
      $self->handle_protocol;
   });
}

sub connected : event_cb {
   my ($self) = @_;
}

sub handle_packet : event_cb {
   my ($self, $hdr, $body) = @_;

   if ($hdr->{cmd} eq 'place_player') {
      $self->{front}->set_player_pos ($hdr->{arg});

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

