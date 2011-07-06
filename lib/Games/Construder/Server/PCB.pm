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
   my ($stmt) = @_;

   my (@tokens);
   while ($stmt ne '') {
      next if $stmt =~ s/^\s+//;

      if ($stmt =~ s/^"([^"]+)"//) {
         push @tokens, [str => $1];
      } elsif ($stmt =~ s/^call:(\S+)//) {
         push @tokens, [call => [str => $1]];
      } elsif ($stmt =~ s/^jump:(\S+)//) {
         push @tokens, [jump => [str => $1]];
      } elsif ($stmt =~ s/^([-+]?(\d+))//) {
         push @tokens, [num => $1];
      } elsif ($stmt =~ s/^(\S+)//) {
         push @tokens, [id => $1];
      } else {
         return [error => $stmt];
      }
   }

   @tokens
}

our %BLTINS = (
   jump   => sub { }, # dummy
   call   => sub { }, # dummy
   return => sub { }, # dummy
   stop   => sub { }, # dummy

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

         if ($blockobj) {
            if ($follow) {
               $self->{p}->{cc} = [@$follow, [str => $blockobj->{name}]]
            } else {
               delete $self->{p}->{wait};
            }
         } else {
            delete $self->{p}->{wait};
         }
      });

      return "wait"
   },
   probe => sub {
   },
   apply => sub {
   },
   print => sub {
      my ($self, $a) = @_;
      $self->{pl}->msg (0, "PCB at @{$self->{pos}} prints: $a");
      return "wait"
   },
   if => sub {
      my ($self, $a, $op, $b, $follow) = @_;
      unless ($follow) {
         return "if: no follow operation specified!";
      }

      my $do_follow;

      if ($a =~ /^[-+0-9]/) {
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
         } else {
            return "compare: unknown op: $op";
         }

      } else {
         if ($op eq '==') {
            $do_follow = ($a eq $b);
         } elsif ($op eq '!=') {
            $do_follow = ($a ne $b);
         } elsif ($op eq '>') {
            $do_follow = ($a > $b);
         } elsif ($op eq '<') {
            $do_follow = ($a < $b);
         } elsif ($op eq '>=') {
            $do_follow = ($a >= $b);
         } elsif ($op eq '<=') {
            $do_follow = ($a <= $b);
         } else {
            return "compare: unknown op: $op";
         }
      }

      if ($do_follow) {
         $self->{p}->{cc} = [@$follow];
         $self->{p}->{wait} = 1;
      }

      return "";
   },
   variable => sub {
   },
   vaporize => sub {
   },
   collect => sub {
   },
   build => sub {
   },
   inv_full => sub {
   },
);

sub parse {
   my ($self) = @_;

   my $t     = $self->{p}->{txt};
   my @stmts = split /(;|\r?\n)/, $t;

   my @ops;

   for my $s (@stmts) {
      if ($s =~ /^\s*(\S+):(.*)/) {
         $self->{p}->{lbl}->{$1} = scalar @ops;
         $s = $2;
      }

      my ($first, @args) = _tokens ($s);
      next unless defined $first;

      if ($first->[0] eq 'error') {
         return "Bad token found: '$first->[1]'";
      } elsif ($first->[0] ne 'id') {
         return "Statement must start with an identifier and not a @$first";
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

   warn "STEP $self->{p}->{wait} $self->{p}->{cc} $self->{p}->{ip}\n";

   $self->{p}->{pad}->{pos_x} = $self->{pos}->[0];
   $self->{p}->{pad}->{pos_y} = $self->{pos}->[1];
   $self->{p}->{pad}->{pos_z} = $self->{pos}->[2];

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

Copyright 2009 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

