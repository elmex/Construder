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

   $self->{con}->ctcp_auto_reply ('VERSION', ['VERSION', "Games-Construder:$Games::Construder::VERSION\:Perl"]);
   $self->{con}->ctcp_auto_reply ('PING', sub { ['PING', $_[4]] });

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
         $self->check_chat_update;
      },
      connect => sub {
         my ($con, $err) = @_;
         $con->{connected} = 1; # FIXME: AE::IRC needs a fix :/
         if ($err) {
            $self->chat_log (error => "Connecting to $con->{host}:$con->{port} failed: $err");
         } else {
            $self->chat_log (info => "Connected to $con->{host}:$con->{port}.");
         }

         $self->{show_hud} = 1;
         $self->show_hud;

         $self->check_chat_update;
      },
      error => sub {
         my ($con, $code, $msg, $ircmsg) = @_;
         $self->chat_log (error => "IRC Error: $code, $msg");
      },
      privatemsg => sub {
         my ($con, $nick, $ircmsg) = @_;
         my $n = prefix_nick ($ircmsg);
         my $msg = sprintf "{%s} %s", $n, $ircmsg->{params}->[-1];
         if ($ircmsg->{command} eq 'NOTICE') {
            $self->chat_log (info => $msg);
         } else {
            $self->chat_log (private => $msg);
            unless ($self->{privhelp}->{$n}) {
               $self->chat_log (info => "(private message from '$n', answer with '/msg $n <your message here>')");
               $self->{privhelp}->{$n} = 1;
            }
         }
      },
      publicmsg => sub {
         my ($con, $targ, $ircmsg) = @_;
         if ($ircmsg->{command} eq 'NOTICE') {
            $self->chat_log (info => sprintf "{%s} %s", prefix_nick ($ircmsg), $ircmsg->{params}->[-1]);
            return;
         }

         my $nick = $con->nick;
         if ($ircmsg->{params}->[-1] =~ /^\b$nick\b/i) {
            $self->chat_log (public_hl =>
               sprintf "<%s> %s",
                  prefix_nick ($ircmsg), $ircmsg->{params}->[-1]);
         } else {
            $self->chat_log (public =>
               sprintf "<%s> %s",
                  prefix_nick ($ircmsg), $ircmsg->{params}->[-1]);
         }
      },
      ctcp_action => sub {
         my ($con, $src, $targ, $msg, $type) = @_;
         if ($con->is_channel_name ($targ)) {
            $self->chat_log (public => sprintf "* %s %s", $src, $msg);
         } else {
            $self->chat_log (private => sprintf "* %s %s", $src, $msg);
         }
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
   my $srv_chat = $self->{front}->{res}->{config}->{srv_chat};
   my $nick = $settings->{nick} ne '' ? $settings->{nick} : $settings->{recent_login_name};
   my $chan = $settings->{chan} ne '' ? $settings->{chan} : $srv_chat->{channel};
   my $host = $settings->{host} ne '' ? $settings->{host} : $srv_chat->{host};
   my $port = $settings->{port} ne '' ? $settings->{port} : $srv_chat->{port};

   ($nick, $chan, $host, $port)
}

sub check_chat_update {
   my ($self) = @_;
   if ($self->{front}->{active_uis}->{irc_chat}) {
      $self->show;
   }
   if ($self->{front}->{active_uis}->{irc_chat_hud}) {
      $self->show_hud;
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
            ui_key_inline_expl (F6 => "Show Chat"),
            ui_key_inline_expl (c => "Toggle HUD Chat"),
            ui_desc ("Chat Status: "
                     . ($self->{con}->is_connected ? "connected" : "disconnected")),
            ($self->{con}->is_connected
               ? ui_select_item (chat_conn => "disconnect", ui_subtext ("Disconnect"))
               : ui_select_item (chat_conn => "connect",    ui_subtext ("Connect"))),
            ui_pad_box (hor =>
               ui_desc ("Used Nickname: "), ui_subdesc ($nick)),
            ui_pad_box (hor =>
               ui_desc ("Custom Nickname:"),
               ui_entry (cust_nick => $settings->{nick}, 10)),
         )
      },
      commands => {
         default_keys => { return => "set", f6 => "chat", c => "hud" }
      },
      command_cb => sub {
         my ($cmd, $arg, $need_selection) = @_;

         if ($cmd eq 'set') {
            $settings->{nick} = $arg->{cust_nick};
            $settings->{host} = $arg->{cust_host};
            $settings->{port} = $arg->{cust_port};
            if ($arg->{chat_conn} eq 'connect') {
               $self->chat_connect;
            } elsif ($arg->{chat_conn} eq 'disconnect') {
               $self->chat_disconnect;
            }
            $self->{front}->{res}->save_config;
            $self->check_connection;
            $self->show;
            return 1;

         } elsif ($cmd eq 'hud') {
            $self->{show_hud} = not $self->{show_hud};
            $self->show_hud;

         } elsif ($cmd eq 'chat') {
            $self->{mode} = "chat";
            $self->show;
            return 1;
         }
      }
   });
}

sub chat_connect {
   my ($self) = @_;
   my ($nick, $chan, $host, $port, $connect) = $self->get_chat_settings;
   my $info = { nick => $nick, real => "G:C:C $Games::Construder::VERSION ($^O)" };
   $self->{con}->connect ($host, $port, $info);
}

sub chat_disconnect {
   my ($self) = @_;
   $self->{con}->disconnect ("user request");
}

sub check_connection {
   my ($self) = @_;

   my ($nick, $chan, $host, $port, $connect) = $self->get_chat_settings;

   if ($self->{con}->registered) {
      if ($self->{con}->nick ne $nick) {
         $self->{con}->send_srv (NICK => $nick);
      }
   }
}

sub show_hud {
   my ($self) = @_;
   unless ($self->{show_hud}) {
      $self->{front}->deactivate_ui ('irc_chat_hud');
      return;
   }

   my @txt = $self->chat_backlog_as_ui (4, 0, "small");

   $self->{front}->activate_ui (irc_chat_hud => {
      %{
         ui_hud_window_transparent (
            [left => "center", 0, 0.15], ui_border (@txt))
      }
   });

}

sub chat_backlog_as_ui {
   my ($self, $lines, $scroll, $font) = @_;
   $font = "normal" if $font eq '';
   my @backlog = @{$self->{backlog}};

   my @txt;
   for (my $i = 0; $i < $lines; $i++) {
      my $l = pop @backlog
         or last;
      my ($type, $txt) = @$l;
      my $txt = sprintf "%7s: %s", $type, $txt;
      if ($type eq 'public') {
         $txt = [text => { font => $font, align => "left", wrap => -60, color => "#ffffff" }, $txt];
      } elsif ($type eq 'public_hl') {
         $txt = [text => { font => $font, align => "left", wrap => -60, color => "#ffffaa" }, $txt];
      } elsif ($type eq 'private') {
         $txt = [text => { font => $font, align => "left", wrap => -60, color => "#ffaaaa" }, $txt];
      } elsif ($type eq 'error') {
         $txt = [text => { font => $font, align => "left", wrap => -60, color => "#ff0000" }, $txt];
      } elsif ($type eq 'info') {
         $txt = [text => { font => $font, align => "left", wrap => -60, color => "#6666FF" }, $txt];
      } else {
         $txt = [text => { font => $font, align => "left", wrap => -60, color => "#dddddd" }, $txt];
      }
      unshift @txt, $txt;
   }

   @txt
}

sub show_chat {
   my ($self) = @_;

   my $mode = $self->{mode};

   my @txt = $self->chat_backlog_as_ui (12);

   $self->{front}->activate_ui (irc_chat => {
      %{
         ui_window (($mode eq 'community' ? "Community Chat" : "Chat"),
            ui_border (@txt),
            ui_border (ui_pad_box (hor =>
               ui_subdesc ("Entry: "), ui_entry_small (irc => "", 90)
            )),
            ui_key_inline_expl (return => "Send message"),
            ui_key_inline_expl ("page up"   => "Scroll backlog up"),
            ui_key_inline_expl ("page down" => "Scroll backlog down"),
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
            if ($arg->{irc} =~ /^\s*\/(\S+)\s*(.*)/) {
               my ($c, $a) = ($1, $2);
               if ($c eq 'msg' && $a =~ /(\S+)\s+(.*)$/) {
                  $self->{con}->send_srv (PRIVMSG => $1, $2);
                  $self->chat_log (private => sprintf "<%s -> %s> %s", $self->{con}->nick, $1, $2);
               } else {
                  $self->chat_log (error => "unknown command: /$c");
               }

            } else {
               $self->{con}->send_srv (PRIVMSG => $chan, $arg->{irc});
               $self->chat_log (public => sprintf "<%s> %s", $self->{con}->nick, $arg->{irc});
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

