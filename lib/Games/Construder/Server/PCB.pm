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
package Games::Construder::Server::PCB;
use common::sense;

=head1 NAME

Games::Construder::Server::PCB - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Construder::Server::PCB->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   return $self
}

sub _tokens {
   my ($line) = @_;

   my @stmts;

   my (@tokens);
   while ($line ne '') {
      next if $line =~ s/^\s+//;

      if ($line =~ s/^"([^"]*)"//) {
         push @tokens, [str => $1];
      } elsif ($line =~ s/^call:(\S+)//) {
         push @tokens, [call => [str => $1]];
      } elsif ($line =~ s/^jump:(\S+)//) {
         push @tokens, [jump => [str => $1]];
      } elsif ($line =~ s/^;//) {
         push @stmts, [@tokens];
         (@tokens) = ();
         next;
      } elsif ($line =~ s/^#.*$//) {
         next;
      } elsif ($line =~ s/^(\S+?)://) {
         push @tokens, [label => $1];
      } elsif ($line =~ s/^([-+]?(\d+))//) {
         push @tokens, [num => $1];
      } elsif ($line =~ s/^\$(\S+)//) {
         push @tokens, [id => $1];
      } elsif ($line =~ s/^(\S+)//) {
         push @tokens, [str => $1];
      } else {
         return [error => $line];
      }
   }

   push @stmts, [@tokens] if @tokens;

   @stmts
}

our %ROTMAP = (
   left => {
      forward   => "left",
      left      => "backward",
      backward  => "right",
      right     => "forward",
      up        => "up",
      down      => "down",
   },
   right => {
      forward   => "right",
      right     => "backward",
      backward  => "left",
      left      => "forward",
      up        => "up",
      down      => "down",
   },
   up => {
      forward   => "up",
      up        => "backward",
      backward  => "down",
      down      => "forward",
      left      => "left",
      right     => "right",
   },
   down => {
      forward   => "down",
      down      => "backward",
      backward  => "up",
      up        => "forward",
      left      => "left",
      right     => "right",
   },
   forward => {
      up        => "left",
      left      => "down",
      down      => "right",
      right     => "up",
      forward   => "forward",
      backward  => "backward",
   },
   backward => {
      up        => "right",
      right     => "down",
      down      => "left",
      left      => "up",
      forward   => "forward",
      backward  => "backward",
   },
   opposite => {
      up       => "down",
      down     => "up",
      left     => "right",
      right    => "left",
      forward  => "backward",
      backward => "forward",
   }
);

our %BLTINS = (
   jump   => sub { }, # dummy
   call   => sub { }, # dummy
   return => sub { }, # dummy
   stop   => sub { }, # dummy

   mat => sub {
      my ($self, $dir, $name, $color, $follow) = @_;
      if (ref $dir) {
         return "mat: bad direction: @$dir"
      }

      unless (grep { $dir eq $_ } qw/up down forward backward left right/) {
         return "mat: unknown direction: '$dir'";
      }

      if ($color < 0 || $color > 15) {
         return "mat: color out of range (0-15): '$color'";
      }

      $self->{p}->{wait} = 1;

      $self->{act}->(materialize => $dir, $name, $color, sub {
         my ($error, $blockobj) = @_;

         $self->{p}->{pad}->{mat_error} = $error;
         $self->{p}->{pad}->{mat}       = $blockobj;

         if ($error ne '' && $follow) {
            $self->{p}->{cc} = [@$follow, [str => $error], [str => $blockobj]]

         } else {
            delete $self->{p}->{wait};
         }
      });

      "wait"
   },

   vapo => sub {
      my ($self, $dir, $follow) = @_;
      if (ref $dir) {
         return "vapo: bad direction: @$dir"
      }

      unless (grep { $dir eq $_ } qw/up down forward backward left right/) {
         return "vapo: unknown direction: '$dir'";
      }

      $self->{p}->{wait} = 1;
      $self->{act}->(vaporize => $dir, sub {
         my ($name) = @_;

         $self->{p}->{pad}->{vapo} = $name;

         if ($follow) {
            $self->{p}->{cc} = [@$follow, [str => $name]]
         } else {
            delete $self->{p}->{wait};
         }
      });

      "wait"
   },

   move => sub {
      my ($self, $dir, $follow) = @_;
      if (ref $dir) {
         return "move: bad direction: @$dir"
      }

      unless (grep { $dir eq $_ } qw/up down forward backward left right/) {
         return "move: unknown direction: '$dir'";
      }

      $self->{p}->{wait} = 1;

      $self->{act}->(move => $dir, sub {
         my ($blockobj) = @_;

         $self->{p}->{pad}->{move} = $blockobj;

         if ($blockobj ne "" && $follow) {
            $self->{p}->{cc} = [@$follow, [str => $blockobj]]
         } else {
            delete $self->{p}->{wait};
         }
      });

      "wait"
   },
   probe => sub {
      my ($self, $dir, $follow) = @_;
      if (ref $dir) {
         return "probe: bad direction: @$dir"
      }

      unless (grep { $dir eq $_ } qw/up down forward backward left right/) {
         return "probe: unknown direction: '$dir'";
      }

      $self->{p}->{wait} = 1;
      $self->{act}->(probe => $dir, sub {
         my ($name) = @_;

         $self->{p}->{pad}->{probe} = $name;

         if ($follow) {
            $self->{p}->{cc} = [@$follow, [str => $name]]
         } else {
            delete $self->{p}->{wait};
         }
      });

      "wait"
   },
   demat => sub {
      my ($self, $dir, $follow) = @_;
      if (ref $dir) {
         return "demat: bad direction: @$dir"
      }

      unless (grep { $dir eq $_ } qw/up down forward backward left right/) {
         return "demat: unknown direction: '$dir'";
      }

      $self->{p}->{wait} = 1;
      $self->{act}->(dematerialize => $dir, sub {
         my ($error, $name) = @_;

         $self->{p}->{pad}->{demat_error} = $error;
         $self->{p}->{pad}->{demat} = $name;

         if ($follow) {
            $self->{p}->{cc} = [@$follow, [str => $error], [str => $name]]
         } else {
            delete $self->{p}->{wait};
         }
      });

      "wait"
   },
   apply => sub {
   },
   wait => sub { "wait" },
   print => sub {
      my ($self, @a) = @_;
      $self->{pl}->msg (0, "PCB at @{$self->{pos}}: " . join ('', @a));
      return "wait"
   },
   if => sub {
      my ($self, $a, $op, $b, $follow) = @_;
      unless ($follow) {
         return "if: no follow operation specified!";
      }

      my $do_follow;
      warn "IF A'$a'$op'$b'\n";

      if ($op eq '==') {
         $do_follow = ($a == $b);
      } elsif ($op eq '!=') {
         $do_follow = ($a != $b);
      } elsif ($op eq '>') {
         $do_follow = ($a > $b);
      } elsif ($op eq '<') {
         $do_follow = ($a < $b);
      } elsif ($op eq '>=') {
         $do_follow = ($a >= $b);
      } elsif ($op eq '<=') {
         $do_follow = ($a <= $b);
      } elsif ($op eq 'eq') {
         $do_follow = ($a eq $b);
      } elsif ($op eq 'ne') {
         $do_follow = ($a ne $b);
      } else {
         return "compare: unknown op: $op";
      }

      if ($do_follow) {
         $self->{p}->{cc} = [@$follow];
         $self->{p}->{wait} = 1;
      }

      return "";
   },
   var => sub {
      my ($self, $varname, $op, $value, $out) = @_;
      my $rv = \$self->{p}->{pad}->{$varname};

      if ($op eq 'add') {
         $$rv += $value;
      } elsif ($op eq 'sub') {
         $$rv -= $value;
      } elsif ($op eq 'mul') {
         $$rv *= $value;
      } elsif ($op eq 'div') {
         $$rv /= $value if $value != 0;
      } elsif ($op eq 'mod') {
         $$rv %= $value if $value != 0;
      } elsif ($op eq 'set') {
         $$rv = $value;
      } elsif ($op eq 'append') {
         $$rv .= $value;
      } elsif ($op eq 'prepend') {
         $$rv = $value . $$rv;

      } elsif ($op eq 'pop') {
         my (@elems) = split /,/, $$rv, -1;
         $self->{p}->{pad}->{$value} = pop @elems;
         $$rv = join ",", @elems;

      } elsif ($op eq 'shift') {
         my (@elems) = split /,/, $$rv, -1;
         $self->{p}->{pad}->{$value} = shift @elems;
         $$rv = join ",", @elems;

      } elsif ($op eq 'unshift') {
         if ($$rv eq '') {
            $$rv = $value
         } else {
            $$rv = "$value," . $$rv
         }

      } elsif ($op eq 'push') {
         if ($$rv eq '') {
            $$rv = $value
         } else {
            $$rv .= ",$value"
         }

      } elsif ($op eq 'at') {
         my (@elems) = split /,/, $$rv, -1;
         if ($value > 0 && $value < @elems) {
            $self->{p}->{pad}->{$out} = $elems[$value];
         }

      } elsif ($op eq 'turn') {
         my $map = $ROTMAP{$value};
         unless ($map) {
            return "var turn: can't turn in unknown direction '$value'";
         }
         my $new = $map->{$$rv};
         if ($new eq '') {
            return "var turn: variable $varname contains unknown direction '$$rv'";
         }
         $$rv = $new;

      } else {
         return "var: unknown operation '$op'";

      }

      return ""
   },
   inv_full => sub {
      my ($self, $name, $follow) = @_;
   },
);

sub parse {
   my ($self) = @_;

   my $t     = $self->{p}->{txt};
   my @lines = split /\r?\n/, $t;

   my @stmts;
   for my $l (@lines) {
      push @stmts, _tokens ($l);
   }

   my @ops;

   for my $s (@stmts) {
      my ($first, @args) = @$s;
      next unless defined $first;

      if ($first->[0] eq 'label') {
         $self->{p}->{lbl}->{$first->[1]} = scalar @ops;
         next;
      }

      if ($first->[0] eq 'error') {
         return "Bad token found: '$first->[1]'";
      } elsif ($first->[0] ne 'str') {
         return "Statement must start with a string and not a @$first";
      }

      push @ops, [$first->[1], @args];
   }

   for (@ops) {
      if (not (exists $BLTINS{$_->[0]})
          && not (exists $self->{p}->{lbl}->{$_->[0]})) {
         return "Direct call to unknown label or builtin found : '$_->[0]'";
      }
   }

   $self->{p}->{ops} = \@ops;
   ""
}

sub clear {
   my ($self) = @_;
   $self->{p}->{stack} = [];
   $self->{p}->{ip}    = 0;
   $self->{p}->{pad}   = {};
   delete $self->{p}->{cc};
   delete $self->{p}->{wait};
}

sub step {
   my ($self, $pre_step) = @_;

   $self->{p}->{pad}->{pos_x} = $self->{pos}->[0];
   $self->{p}->{pad}->{pos_y} = $self->{pos}->[1];
   $self->{p}->{pad}->{pos_z} = $self->{pos}->[2];
   $self->{p}->{pad}->{energy_used} = $self->{energy_used};
   $self->{p}->{pad}->{energy_left} = $self->{energy_left};

   if ($self->{p}->{wait}) {
      my $cc = delete $self->{p}->{cc}
         or return "wait";

      $pre_step = $cc;
      delete $self->{p}->{wait}
   }

   my $ops = $self->{p}->{ops};
   my $rip = \$self->{p}->{ip};

   my ($call, @args) = $pre_step ? @$pre_step : @{$ops->[$$rip++] || []};
   unless (defined $call) {
      $call = "stop";
   }

   my (@res) = map {
       $_->[0] eq 'str' ? $_->[1]
     : $_->[0] eq 'id'  ? $self->{p}->{pad}->{$_->[1]}
     : $_->[0] eq 'num' ? ($_->[1] * 1)
     : $_
   } @args;

   warn "PCB EXEC: @ $$rip | $call @args => @res\n";

   if ($call eq 'jump') {
      my $lbl = shift @res;
      return "exception: can't jump to '$lbl', no such label!"
         unless exists $self->{p}->{lbl}->{$lbl};

      my $i = 0;
      $self->{p}->{pad}->{"arg" . ($i++)} = $_
         for @res;
      $$rip = $self->{p}->{lbl}->{$lbl};
      return "";

   } elsif ($call eq 'call') {
      my $lbl = shift @res;
      $call = $lbl;
      # fall through!

   } elsif ($call eq 'return') {
      my $i = 0;
      $self->{p}->{pad}->{"ret" . ($i++)} = $_
         for @res;
      $$rip = pop @{$self->{p}->{stack}};
      return "";

   } elsif ($call eq 'stop') {
      $self->clear;
      my $i = 0;
      $self->{p}->{pad}->{"result" . ($i++)} = $_
         for @res;
      return "done";
   }

   my $b = $BLTINS{$call};
   if ($b) {
      return $b->($self, @res);

   } else {
      return "exception: can't call '$call', no such label!"
         unless exists $self->{p}->{lbl}->{$call};

      push @{$self->{p}->{stack}}, $$rip;

      if (@{$self->{p}->{stack}} > 500000) {
         return "exception: stack too large, too many calls without return!";
      }

      my $i = 0;
      $self->{p}->{pad}->{"arg" . ($i++)} = $_
         for @res;
      $$rip = $self->{p}->{lbl}->{$call};
   }

   return ""
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

