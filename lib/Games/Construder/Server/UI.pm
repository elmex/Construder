package Games::Construder::Server::UI;
use common::sense;
use Scalar::Util qw/weaken/;
require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   ui_player_score
   ui_player_bio_warning
   ui_player_tagger
/;

=head1 NAME

Games::Construder::Server::UI - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   weaken $self->{pl};

   return $self
}

sub layout {
   my ($self, @args) = @_;
}

sub reg_cmd {
   my ($self, $key, $cb) = @_;
   my $n = $self->{ui_name} . '_' . $key;
   $self->{cmds}->{$key} = $n;
   $self->{cbs}->{$n} = $cb;
}

sub commands {
   my ($self) = @_;
   my $cmdname = 1;
   {
      map {
         $_ => $self->{cmds}->{$_}
      } keys %{%self->{cmds}}
   }
}

sub update {
   my ($self, @args) = @_;
   $self->show (@args) if $self->{shown};
}

sub show {
   my ($self, @args) = @_;
   my $lyout = $self->layout (@args);
   $lyout->{commands}->{default_keys} = $self->commands;

   $self->{pl}->display_ui ($self->{ui_name} => $lyout);
}

sub react {
   my ($self, $cmd, $arg, $pos) = @_;
   return unless $self->{shown};

   my $cb = $self->{cbs}->{$cmd}
      or return;
   $cb->($arg, $pos);
}

sub hide {
   my ($self) = @_;
   $self->{pl}->display_ui ($self->{ui_name});
}

sub DESTROY {
   my ($self) = @_;
   $self->{pl}->display_ui ($self->{ui_name});
}

package Games::Construder::Server::UI::Score;

use base qw/Games::Construder::Server::UI/;

sub layout {
   my ($self, $hl) = @_;

   if ($hl) {
      my $wself = $self;
      weaken $wself;
      $self->{upd_score_hl_tmout} = AE::timer 1.5, 0, sub {
         $wself->show;
         delete $self->{upd_score_hl_tmout};
      };
   }

   my $score =  $self->{pl}->{data}->{score};

   {
      window => {
         sticky  => 1,
         pos     => [center => "up"],
         alpha   => $hl ? 1 : 0.6,
      },
      layout => [
         box => {
            border  => { color => $hl ? "#ff0000" : "#777700" },
            padding => ($hl ? 10 : 2),
            align   => "hor",
         },
         [text => {
            font  => "normal",
            color => "#aa8800",
            align => "center"
          }, "Score:"],
         [text => {
            font  => "big",
            color => $hl ? "#ff0000" : "#aa8800",
          }, ($score . ($hl ? "+$hl" : ""))]
      ]
   }
}

package Games::Construder::Server::UI::BioWarning;

use base qw/Games::Construder::Server::UI/;

sub layout {
   my ($self, $seconds) = @_;

   {
      window => {
         sticky => 1,
         pos    => [center => 'center', 0, -0.15],
         alpha  => 0.3,
      },
      layout => [
         box => { dir => "vert" },
         [text => { font => "big", color => "#ff0000", wrap => 28, align => "center" },
          "Warning: Bio energy level low! You have $seconds seconds left!\n"],
         [text => { font => "normal", color => "#ff0000", wrap => 35, align => "center" },
          "Death imminent, please dematerialize something that provides bio energy!"],
      ]
   }
}

package Games::Construder::Server::UI::MsgBox;

use base qw/Games::Construder::Server::UI/;

sub layout {
   my ($self, $error, $msg) = @_;

   my $wself = $self;
   weaken $wself;
   $self->{msg_tout} = AE::timer (($error ? 3 : 1), 0, sub {
      $wself->hide;
      delete $self->{msg_tout};
   });

   {
      window => {
         pos => [center => "center", 0, 0.25],
         alpha => 0.6,
      },
      layout => [
         text => { font => "big", color => $error ? "#ff0000" : "#ffffff", wrap => 20 },
         $msg
      ]
   }
}

sub ui_player_location_book {
   my ($pl, $fetch, $set) = @_;

   $pl->displayed_uis (location_book => {
      window => {
      },
      layout => [
      ],
      commands => {
         default_keys => {
            return => "set"
         }
      }
   });
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

