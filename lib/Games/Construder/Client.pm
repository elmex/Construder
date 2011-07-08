# Games::Construder - A 3D Game written in Perl with an infinite and modifiable world.
# Copyright (C) 2011  Robin Redeker
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
package Games::Construder::Client;
use common::sense;
use Compress::LZF;
use Games::Construder::Client::Frontend;
use Games::Construder::Client::World;
use Games::Construder::Protocol;
use Games::Construder::Vector;
use Games::Construder;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Benchmark qw/:all/;
use Time::HiRes qw/time/;

use base qw/Object::Event/;

=head1 NAME

Games::Construder::Client - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Construder::Client->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;

   Games::Construder::World::init (sub {
   }, sub { });

   $self->{res} = Games::Construder::Client::Resources->new;
   $self->{res}->init_directories;
   $self->{res}->load_config;
   $Games::Construder::Client::UI::RES = $self->{res};

   $self->{front} =
      Games::Construder::Client::Frontend->new (res => $self->{res}, client => $self);

   $self->{front}->reg_cb (
      update_player_pos => sub {
         $self->send_server ({
            cmd => "p", p => vcompres ($_[1]), l => vcompres ($_[2])
         });
      },
      position_action => sub {
         my ($front, $pos, $build_pos, $btn) = @_;
         $self->send_server ({
            cmd => "pos_action", pos => $pos,
            build_pos => $build_pos, action => $btn
         });
      },
      visibility_radius => sub {
         my ($front, $radius) = @_;
         $self->send_server ({ cmd => "visibility_radius", radius => $radius });
      },
      visible_chunks_changed => sub {
         my ($front, $new, $old, $req) = @_;
 #        warn "NEW: @$new, OLD @$old\n";
         (@$req) = grep {
            my $p = $_;
            my $id = world_pos2id ($p);
            my $rereq = 1;
            if ($self->{requested_chunks}->{$id}) {
               $rereq =
                  (time - $self->{requested_chunks}->{$id}) > 2;
               if ($rereq) {
                  warn "re-requesting chunk $id!\n";
               }
            }
            if ($rereq) {
               $self->{requested_chunks}->{$id} = time;
            }
            $rereq
         } @$req; # Frontend will retry until it succeeds (at least it should)!
         return unless @$new || @$old || @$req;
         $self->send_server ({ cmd => "vis_chunks", old => $old, new => $new, req => $req });
      }
   );

   $self->connect ($ARGV[1] || localhost => $ARGV[2] || 9364);

   return $self
}

sub start {
   my ($self) = @_;

   my $c = AnyEvent->condvar;

   $c->recv;
}

sub reconnect {
   my ($self) = @_;
   $self->connect ($self->{host}, $self->{port});
}

sub connect {
   my ($self, $host, $port) = @_;

   ($self->{host}, $self->{port}) = ($host, $port);

   delete $self->{recon};
   tcp_connect $host, $port, sub {
      my ($fh) = @_;
      unless ($fh) {
         $self->{front}->msg ("Couldn't connect to server: $!");
         $self->{recon} = AE::timer 5, 0, sub { $self->reconnect; };
         return;
      }

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
   $self->{front}->msg ("Connected to Server!");
   $self->send_server ({ cmd => 'hello', version => "Games::Construder::Client 0.1" });
}

sub handle_packet : event_cb {
   my ($self, $hdr, $body) = @_;

   warn "cl< $hdr->{cmd} (".length ($body).")\n";

   if ($hdr->{cmd} eq 'hello') {
      $self->{front}->{server_info} = $hdr->{info};
      $self->{front}->msg ("Queried Resources");
      $self->send_server ({ cmd => 'list_resources' });

   } elsif ($hdr->{cmd} eq 'resources_list') {
      $self->{res}->set_resources ($hdr->{list});

      #  [ $_, $res->{type}, $res->{md5}, \$res->{data} ]
      my @data_res_ids = map { $_->[0] } grep { defined $_->[2] } @{$hdr->{list}};

      if (@data_res_ids) {
         $self->send_server ({ cmd => get_resources => ids => \@data_res_ids });
         $self->{front}->msg ("Initiated resource transfer (".scalar (@data_res_ids).")");
      } else {
         $self->{front}->msg ("No resources on server found!");
      }

   } elsif ($hdr->{cmd} eq 'resource') {
      my $res = $hdr->{res};
      #  [ $_, $res->{type}, $res->{md5}, \$res->{data} ]
      $self->{res}->set_resource_data ($hdr->{res}, $body);
      $self->send_server ({ cmd => 'transfer_poll' });

   } elsif ($hdr->{cmd} eq 'transfer_end') {
      $self->{front}->msg;
      #print JSON->new->pretty->encode ($self->{front}->{res}->{resource});
      $self->{res}->post_proc;
      $self->{res}->dump_resources;
      $self->send_server (
         { cmd => 'login',
           ($self->{auto_login} ? (name => $self->{auto_login}) : ()) });

   } elsif ($hdr->{cmd} eq 'place_player') {
      $self->{front}->set_player_pos ($hdr->{pos});
      $self->send_server ({ cmd => 'set_player_pos_ok', id => $hdr->{id} });

   } elsif ($hdr->{cmd} eq 'activate_ui') {
      my $desc = $hdr->{desc};
      $desc->{command_cb} = sub {
         my ($cmd, $arg, $need_selection) = @_;

         $self->send_server ({
            cmd => 'ui_response' =>
               ui => $hdr->{ui}, ui_command => $cmd, arg => $arg,
               ($need_selection
                  ? (pos => $self->{front}->{selected_box},
                     build_pos => $self->{front}->{selected_build_box})
                  : ())
         });
      };
      $self->{front}->activate_ui ($hdr->{ui}, $desc);

   } elsif ($hdr->{cmd} eq 'deactivate_ui') {
      $self->{front}->deactivate_ui ($hdr->{ui});

   } elsif ($hdr->{cmd} eq 'highlight') {
      $self->{front}->add_highlight ($hdr->{pos}, $hdr->{color}, $hdr->{fade});

   } elsif ($hdr->{cmd} eq 'model_highlight') {
      if ($hdr->{model}) {
         $self->{front}->add_highlight_model ($hdr->{pos}, $hdr->{model}, $hdr->{id});
      } else {
         $self->{front}->remove_highlight_model ($hdr->{id});
      }

   } elsif ($hdr->{cmd} eq 'dirty_chunks') {
      $self->{front}->clear_chunk ($_) for @{$hdr->{chnks}}

   } elsif ($hdr->{cmd} eq 'chunk') {
      my $id = world_pos2id ($hdr->{pos});
      delete $self->{requested_chunks}->{$id};
      $body = decompress ($body);

      # WARNING FIXME XXX: this data might not be freed up all chunks that
      # were set/initialized by the server! see also free_compiled_chunk in Frontend.pm
      my $neigh_chunks =
         Games::Construder::World::set_chunk_data (@{$hdr->{pos}}, $body, length $body);
      if ($neigh_chunks & 0x01) {
         $self->{front}->dirty_chunk (vaddd ($hdr->{pos}, -1, 0, 0));
      }
      if ($neigh_chunks & 0x02) {
         $self->{front}->dirty_chunk (vaddd ($hdr->{pos}, 0, -1, 0));
      }
      if ($neigh_chunks & 0x04) {
         $self->{front}->dirty_chunk (vaddd ($hdr->{pos}, 0, 0, -1));
      }
      if ($neigh_chunks & 0x08) {
         $self->{front}->dirty_chunk (vaddd ($hdr->{pos}, 1, 0, 0));
      }
      if ($neigh_chunks & 0x10) {
         $self->{front}->dirty_chunk (vaddd ($hdr->{pos}, 0, 1, 0));
      }
      if ($neigh_chunks & 0x20) {
         $self->{front}->dirty_chunk (vaddd ($hdr->{pos}, 0, 0, 1));
      }
      $self->{front}->dirty_chunk ($hdr->{pos});

   } elsif ($hdr->{cmd} eq 'msg') {
      $self->{front}->msg ("Server: " . $hdr->{msg});
   }
}

sub disconnected : event_cb {
   my ($self) = @_;
   delete $self->{srv};
   $self->{front}->msg ("Disconnected from server!");
   $self->{recon} = AE::timer 5, 0, sub { $self->reconnect; };
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License.

=cut

1;

