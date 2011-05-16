package Games::Blockminer3D::Server;
use common::sense;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use JSON;

use Games::Blockminer3D::Protocol;
use Games::Blockminer3D::Server::Resources;
use Games::Blockminer3D::Server::Player;
use Games::Blockminer3D::Server::World;
use Games::Blockminer3D::Server::ChunkManager;

use base qw/Object::Event/;

=head1 NAME

Games::Blockminer3D::Server - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Server->new (%args)

=cut

our $RES;
our $CHNK;

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

   $RES = Games::Blockminer3D::Server::Resources->new;
   $RES->init_directories;
   $RES->load_objects;

   $CHNK = Games::Blockminer3D::Server::ChunkManager->new;
   $CHNK->init;

   # active objects verwaltung
   #    - player
   #       inventory / aktive objekte
   #    - chunks
   #       chunk id => position, liste der aktiven objekte
   # => aber wie die einzelnen entities identifizieren?!
   #    evtl. unique-id einführen und beim laden
   #    in eine globale liste einfügen?
   #    => währe also ambesten eine 32 (oder 28) Bit ID an der Entity
   #      => könnte erzeugt werden aus timestamp oder sowas....
   #         oder besser: globaler counter
   #
   # speicherung evtl. einfach als liste von objekten im json
   # laden genauso, record enthält beim laden aber position in der map
   #                position kann sich aber ändern:
   #                - 2 typen ovn positionen: in chunk, in player

   world_init (sub {
      my ($x, $y, $z, $action, $offsetid) = @_;
      # $action   => remove (-1), add (1), undefined (0/undef)
      # $offsetid => id des objekts
      warn "CHUNK CHANGED (@_)\n";
      $CHNK->chunk_changed (@_);
      my $chnk = [@_];
      for (values %{$self->{players}}) {
         $_->chunk_updated ($chnk);
      }
   });
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

sub transfer_res2client {
   my ($self, $cid, $res) = @_;
   $self->{transfer}->{$cid} = [
      map {
         my $body = "";
         if (defined ${$_->[-1]} && not (ref ${$_->[-1]})) {
            $body = ${$_->[-1]};
            $_->[-1] = undef;
         } else {
            $_->[-1] = ${$_->[-1]};
         }
         warn "PREPARE RESOURCE $_->[0]: " . length ($body) . "\n";
         packet2data ({
            cmd => "resource",
            res => $_
         }, $body)
      } @$res
   ];
   $self->send_client ($cid, { cmd => "transfer_start" });
   $self->push_transfer ($cid);
}

sub push_transfer {
   my ($self, $cid) = @_;
   my $t = $self->{transfer}->{$cid};
   return unless $t;

   my $data = shift @$t;
   $self->{clients}->{$cid}->push_write (packstring => "N", $data);
   warn "srv($cid)trans(".length ($data).")\n";
   unless (@$t) {
      $self->send_client ($cid, { cmd => "transfer_end" });
      delete $self->{transfer}->{$cid};
   }
}

sub client_disconnected : event_cb {
   my ($self, $cid) = @_;
   my $pl = delete $self->{players}->{$cid};
   $pl->logout if $pl;
   delete $self->{player_guards}->{$cid};
   delete $self->{clients}->{$cid};
   warn "client disconnected: $cid\n";
}

sub client_connected : event_cb {
   my ($self, $cid) = @_;
}

sub handle_player_packet : event_cb {
   my ($self, $player, $hdr, $body) = @_;

   if ($hdr->{cmd} eq 'ui_response') {
      $player->ui_res ($hdr->{ui}, $hdr->{ui_command}, $hdr->{arg});

   } elsif ($hdr->{cmd} eq 'player_pos') {
      $CHNK->check_adjacent_sectors_at ($hdr->{pos});
      $player->update_pos ($hdr->{pos});

   } elsif ($hdr->{cmd} eq 'pos_action') {
      if ($hdr->{action} == 1 && @{$hdr->{build_pos} || []}) {
         $player->start_materialize ($hdr->{build_pos});

      } elsif ($hdr->{action} == 2 && @{$hdr->{build_pos} || []}) {
         $player->set_debug_light ($hdr->{build_pos});

      } elsif ($hdr->{action} == 3 && @{$hdr->{pos} || []}) {
         $player->start_dematerialize ($hdr->{pos});
      }

   }

}

sub handle_packet : event_cb {
   my ($self, $cid, $hdr, $body) = @_;

   warn "srv($cid)< $hdr->{cmd}\n";

   if ($hdr->{cmd} eq 'hello') {
      $self->send_client ($cid,
         { cmd => "hello", version => "Games::Blockminer3D::Server 0.1" });

   } elsif ($hdr->{cmd} eq 'ui_response' && $hdr->{ui} eq 'login') {
      $self->send_client ($cid, { cmd => deactivate_ui => ui => "login" });

      if ($hdr->{ui_command} eq 'login') {

         my $pl = $self->{players}->{$cid}
            = Games::Blockminer3D::Server::Player->new (cid => $cid, name => $hdr->{arg}->[0]);

         $self->{player_guards}->{$cid} = $pl->reg_cb (send_client => sub {
            my ($pl, $hdr, $body) = @_;
            $self->send_client ($cid, $hdr, $body);
         });

         $pl->init;

         $self->send_client ($cid,
            { cmd => "login" });
      }

   } elsif ($hdr->{cmd} eq 'login') {
      $self->send_client ($cid, { cmd => activate_ui => ui => "login", desc => {
         window => {
            extents => [center => center => 0.4, 0.2],
            alpha => 1,
            color => "#000000",
         },
         elements => [
            {
               type => "text", extents => [0, 0.02, 1, "font_height"],
               align => "center",
               font => "normal", color => "#ffffff",
               text => "Login"
            },
            {
               type => "text", extents => [0.02, "bottom_of 0", "text_width", "font_height"],
               font => "normal", color => "#ffffff",
               text => "Player name:",
               bg_color => "#000000",
            },
            {
               type => "entry",
               extents => ["right_of 1", "bottom_of 0", "text_width normal:mmmmmmm", "font_height"],
               font => "normal", color => "#ffffff",
               bg_color => "#000000",
               hl_color => "#333333",
               max_chars => 7,
               text => ""
            },
         ],
         commands => {
            default_keys => {
               return => "login",
            },
         },
      } });

   } elsif ($hdr->{cmd} eq 'transfer_poll') { # a bit crude :->
      $self->push_transfer ($cid);

   } elsif ($hdr->{cmd} eq 'list_resources') {
      my $res = $RES->list_resources;
      $self->send_client ($cid, { cmd => "resources_list", list => $res });

   } elsif ($hdr->{cmd} eq 'get_resources') {
      my $res = $RES->get_resources_by_id (@{$hdr->{ids}});
      $self->transfer_res2client ($cid, $res);

   } else {
      my $pl = $self->{players}->{$cid}
         or return;

      $self->handle_player_packet ($pl, $hdr, $body);
   }
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

