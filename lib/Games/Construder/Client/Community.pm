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
package Games::Construder::Client::Community;
use common::sense;
use Games::Construder::Logging;
use Games::Construder::UI;
use AnyEvent::IRC::Client;
use AnyEvent::IRC::Util qw/mk_msg filter_colors prefix_nick/;
use base qw/Object::Event/;

=head1 NAME

Games::Construder::Client::Community - Module that implements some community functions

=over 4

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->{con} = AnyEvent::IRC::Client->new;

   $self->{con}->reg_cb (
      registered => sub {
         my ($con) = @_;
         $self->chat_log (info => "Registered successfully as " . $con->nick);
         my ($nick, $chan, $host, $port) = $self->get_chat_settings;
         $con->send_srv (JOIN => $chan);
      },
      disconnect => sub {
         my ($con) = @_;
         $self->chat_log (error => "Disconnected from $con->{host}:$con->{port}: $_[1]");
      },
      connect => sub {
         my ($con, $err) = @_;
         $con->{connected} = 1; # FIXME: AE::IRC needs a fix :/
         if ($err) {
            $self->chat_log (error => "Connecting to $con->{host}:$con->{port} failed: $err");
         } else {
            $self->chat_log (info => "Connected to $con->{host}:$con->{port}.");
         }
      },
      error => sub {
         my ($con, $code, $msg, $ircmsg) = @_;
         $self->chat_log (error => "IRC Error: $code, $msg");
      },
      privatemsg => sub {
         my ($con, $nick, $ircmsg) = @_;
         $self->chat_log (private => "{$nick} $ircmsg->{params}->[-1]");
      },
      publicmsg => sub {
         my ($con, $targ, $ircmsg) = @_;
         $self->chat_log (public =>
            sprintf "<%10s> %s",
               prefix_nick ($ircmsg), $ircmsg->{params}->[-1]);
      },
      quit => sub {
         my ($con, $nick, $msg) = @_;
         $self->chat_log (public => "* $nick quits: $msg");
      },
      kick => sub {
         my ($con, $nick, $chan, $is_me, $msg, $kicker) = @_;
         if ($is_me) {
            $self->chat_log (public => "* $nick was kicked from $chan by $kicker: $msg");
            my $settings = ($self->{front}->{res}->{config}->{chat} ||= {});
            $settings->{con} = "disconnect";
            $self->check_connection;

         } else {
            $self->chat_log (public => "* $nick was kicked from $chan by $kicker: $msg");
         }
      },
      join => sub {
         my ($con, $nick, $chan, $is_myself) = @_;
         if ($is_myself) {
            $con->send_srv (TOPIC => $chan);
         }
         $self->chat_log (public => "* $nick joined $chan");
      },
      part => sub {
         my ($con, $nick, $chan, $is_myself, $msg) = @_;
         $self->chat_log (public => "* $nick parted $chan: $msg");
      },
      channel_topic => sub {
         my ($con, $chan, $topic) = @_;
         $self->{topic} = $topic;
         $self->check_chat_update;
      },
   );

   return $self
}

sub chat_log {
   my ($self, $type, $msg) = @_;

   ctr_log (chat => "$type: $msg");
   push @{$self->{backlog}}, [$type, $msg];
   $self->{backlog_scroll} = 0;
   $self->check_chat_update;
}

sub get_chat_settings {
   my ($self) = @_;
   my $settings = ($self->{front}->{res}->{config}->{chat} ||= {});
   my $nick = $settings->{nick} ne '' ? $settings->{nick} : $settings->{recent_login_name};
   my $chan = $settings->{chan} ne '' ? $settings->{chan} : "#construder";
   my $host = $settings->{host} ne '' ? $settings->{host} : "irc.perl.org";
   my $port = $settings->{port} ne '' ? $settings->{port} : 6667;

   ($nick, $chan, $host, $port, $settings->{con})
}

sub check_chat_update {
   my ($self) = @_;
   if ($self->{mode} eq 'chat' && $self->{front}->{active_uis}->{irc_chat}) {
      $self->show;
   }
}

sub show {
   my ($self) = @_;
   if ($self->{mode} eq 'chat') {
      $self->show_chat;
   } else {
      $self->show_chat_settings;
   }
}

sub show_chat_settings {
   my ($self) = @_;

   my ($nick, $chan, $host, $port, $con) = $self->get_chat_settings;
   my $settings = ($self->{front}->{res}->{config}->{chat} ||= {});

   $self->{front}->activate_ui (irc_chat => {
      %{
         ui_window ("Chat Settings",
            ui_key_explain (F6 => "Show Chat"),
            ui_pad_box (hor =>
               $con eq 'connect'
                 ? ui_select_item (chat_conn => "disconnect", ui_subtext ("Leave Chat"))
                 : ui_select_item (chat_conn => "connect",    ui_subtext ("Enter Chat"))),
            ui_pad_box (hor =>
               ui_desc ("Used Nickname: "), ui_subdesc ($nick)),
            ui_pad_box (hor =>
               ui_desc ("Custom Nickname:"),
               ui_entry (cust_nick => $settings->{nick}, 10)),
            ui_pad_box (hor =>
               ui_desc ("Used Host: "),
               ui_subdesc ($host)),
            ui_pad_box (hor =>
               ui_desc ("Custom Host:"),
               ui_entry (cust_host => $settings->{host}, 30)),
            ui_pad_box (hor =>
               ui_desc ("Used Port: "),
               ui_subdesc ($port)),
            ui_pad_box (hor =>
               ui_desc ("Custom Port:"),
               ui_entry (cust_port => $settings->{port}, 6)),
            ui_pad_box (hor =>
               ui_desc ("Used Channel: "),
               ui_subdesc ($chan)),
            ui_pad_box (hor =>
               ui_desc ("Custom Channel:"),
               ui_entry (cust_chan => $settings->{chan}, 6)),
         )
      },
      commands => {
         default_keys => { return => "set", f6 => "chat" }
      },
      command_cb => sub {
         my ($cmd, $arg, $need_selection) = @_;

         if ($cmd eq 'set') {
            $settings->{nick} = $arg->{cust_nick};
            $settings->{host} = $arg->{cust_host};
            $settings->{port} = $arg->{cust_port};
            $settings->{con}  = $arg->{chat_conn};
            $self->{front}->{res}->save_config;
            $self->check_connection;
            if ($settings->{con} eq 'connect') {
               $self->{mode} = "chat";
            }
            $self->show;
            return 1;

         } elsif ($cmd eq 'chat') {
            $self->{mode} = "chat";
            $self->show;
            return 1;
         }
      }
   });
}

sub check_connection {
   my ($self) = @_;

   my ($nick, $chan, $host, $port, $connect) = $self->get_chat_settings;

   my $info = { nick => $nick, real => "G:C:C $Games::Construder::VERSION ($^O)" };

   if ($connect eq 'connect'
       && !$self->{con}->is_connected
   ) {
      $self->{con}->connect ($host, $port, $info);
      return;
   }

   if ($connect eq 'disconnect'
       && $self->{con}->is_connected
   ) {
      $self->{con}->disconnect ("user request");
      return;
   }

   if ($self->{con}->is_connected) {
      if ($self->{con}->{host} ne $host
          || $self->{con}->{port} ne $port
      ) {
         $self->{con}->connect ($host, $port, $info);
         return;
      }
   }

   if ($self->{con}->registered) {
      if ($self->{con}->nick ne $nick) {
         $self->{con}->send_srv (NICK => $nick);
      }
   }
}

sub show_chat {
   my ($self) = @_;

   my $mode = $self->{mode};

   my @backlog = @{$self->{backlog}};

   my @txt;
   for (my $i = 0; $i < 15; $i++) {
      my $l = pop @backlog
         or last;
      my ($type, $txt) = @$l;
      my $txt = sprintf "%10s: %s", $type, $txt;
      if ($type eq 'public') {
         $txt = [text => { font => "normal", align => "left", wrap => -60, color => "#ffffff" }, $txt];
      } elsif ($type eq 'private') {
         $txt = [text => { font => "normal", align => "left", wrap => -60, color => "#ffaaaa" }, $txt];
      } elsif ($type eq 'error') {
         $txt = [text => { font => "normal", align => "left", wrap => -60, color => "#ff0000" }, $txt];
      } elsif ($type eq 'info') {
         $txt = [text => { font => "normal", align => "left", wrap => -60, color => "#0000dd" }, $txt];
      } else {
         $txt = [text => { font => "normal", align => "left", wrap => -60, color => "#dddddd" }, $txt];
      }
      unshift @txt, $txt;
   }

   $self->{front}->activate_ui (irc_chat => {
      %{
         ui_window (($mode eq 'community' ? "Community Chat" : "Chat"),
            ui_border (
               @txt
            ),
            ui_entry_small (irc => "", 100),
            ui_key_inline_expl (return => "Send message"),
            ui_key_inline_expl ("page up"   => "Scroll backlog up"),
            ui_key_inline_expl ("page down" => "Scroll backlog down"),
 #           ui_key_inline_expl ("F5"        => "Toggle Minichat visibility"),
            ui_key_inline_expl ("F6"        => "Chat Settings"),
            ui_key_inline_expl ("F9"        => "Hide Chat"),
         )
      },
      commands => {
         default_keys => {
            return => "send",
            f6 => "settings",
            f9 => "hide",
         }
      },
      command_cb => sub {
         my ($cmd, $arg, $need_selection) = @_;

         my ($nick, $chan, $host, $port, $connect) = $self->get_chat_settings;

         if ($cmd eq 'send') {
            if ($arg->{irc} =~ /^\/(\S+)\s*(.*)/) {
               my ($c, $a) = ($1, $2);
               if ($c eq 'msg' && $a =~ /(\S+)\s+(.*)$/) {
                  $self->{con}->send_srv (PRIVMSG => $1, $2);
                  $self->chat_log (private => sprintf "<%10s -> %-10s> %s", $self->{con}->nick, $1, $2);
               } else {
                  $self->chat_log (error => "unknown command: /$c");
               }

            } else {
               $self->{con}->send_srv (PRIVMSG => $chan, $arg->{irc});
               $self->chat_log (public => sprintf "<%10s> %s", $self->{con}->nick, $arg->{irc});
            }
            $self->show;
            return 1;

         } elsif ($cmd eq 'settings') {
            $self->{mode} = "settings";
            $self->show;
            return 1;

         } elsif ($cmd eq 'hide') {
            $self->{front}->deactivate_ui ('irc_chat');
         }
      }
   });
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

