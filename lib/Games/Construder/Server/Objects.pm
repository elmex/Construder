package Games::Construder::Server::Objects;
use common::sense;
use Games::Construder::Server::World;
use Games::Construder::Vector;
use Games::Construder;
use Scalar::Util qw/weaken/;

=head1 NAME

Games::Construder::Server::Objects - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

our %TYPES = (
   31 => \&ia_pattern_storage,
   34 => \&ia_message_beacon,
   36 => \&ia_construction_pad,
   45 => \&ia_vaporizer,
   46 => \&ia_vaporizer,
   47 => \&ia_vaporizer,
   48 => \&ia_vaporizer,
   62 => \&ia_teleporter,
);

our %TYPES_INSTANCIATE = (
   31 => \&in_pattern_storage,
   34 => \&in_message_beacon,
   45 => \&in_vaporizer,
   46 => \&in_vaporizer,
   47 => \&in_vaporizer,
   48 => \&in_vaporizer,
   62 => \&in_teleporter,
);

our %TYPES_TIMESENSITIVE = (
   31 => \&tmr_pattern_storage,
   45 => \&tmr_vaporizer,
   46 => \&tmr_vaporizer,
   47 => \&tmr_vaporizer,
   48 => \&tmr_vaporizer,
);

our %TYPES_PERSISTENT = (
   # for pattern storage for instance
   # or a build agent
);

sub interact {
   my ($player, $pos, $type, $entity) = @_;
   my $cb = $TYPES{$type}
      or return;
   $cb->($player, $pos, $type, $entity);
}

sub destroy {
   my ($ent) = @_;
   # nop for now
}

sub instance {
   my ($type) = @_;

   my $cb = $TYPES_INSTANCIATE{$type}
      or return;
   my $i = $cb->($type);
   $i->{type} = $type;
   $i->{tmp} ||= {};
   $i
}

sub tick {
   my ($pos, $entity, $type, $dt) = @_;
   my $cb = $TYPES_TIMESENSITIVE{$type}
      or return;
   $cb->($pos, $entity, $type, $dt)
}

sub in_vaporizer {
   my ($type) = @_;
   my $time = 1;
   if ($type == 46) {
      $time = 2;
   } elsif ($type == 47) {
      $time = 4;
   } elsif ($type == 48) {
      $time = 8;
   }

   {
      time => $time,
   }
}

sub tmr_vaporizer {
   my ($pos, $entity, $type, $dt) = @_;
   warn "vapo tick: $dt ($type, $entity)\n";

   $entity->{tmp}->{accumtime} += $dt;
   if ($entity->{tmp}->{accumtime} >= $entity->{time}) {
      my $rad = $entity->{tmp}->{rad};
      my $pos = $entity->{tmp}->{pos};

      my @poses;
      for my $x (-$rad..$rad) {
         for my $y (-$rad..$rad) {
            for my $z (-$rad..$rad) {
               push @poses, my $p = vaddd ($pos, $x, $y, $z);
            }
         }
      }

      world_mutate_at (\@poses, sub {
         my ($d) = @_;
         $d->[0] = 0;
         $d->[3] &= 0xF0; # clear color :)
         my $ent = $d->[5]; # kill entity
         $d->[5] = undef;
         if ($ent) {
            Games::Construder::Server::Objects::destroy ($ent);
         }
         warn "VAP@$d\n";
         1
      });
   }
}

sub ia_vaporizer {
   my ($PL, $POS, $type, $entity) = @_;


   my $rad = 1; # type == 45
   if ($type ==  46) {
      $rad = 2;
   } elsif ($type ==  47) {
      $rad = rand (100) > 20 ? 5 : 0;
   } elsif ($type ==  48) {
      $rad = rand (100) > 60 ? 10 : int (rand () * 9) + 1;
   }

   my $time = $entity->{time};
   my (@pl) =
      $Games::Construder::Server::World::SRV->players_near_pos ($POS);
   for my $x (-$rad..$rad) {
      $_->highlight (vaddd ($POS, $x, 0, 0), $time, [1, 1, 0]) for @pl;
   }
   for my $y (-$rad..$rad) {
      $_->highlight (vaddd ($POS, 0, $y, 0), $time, [1, 1, 0]) for @pl;
   }
   for my $z (-$rad..$rad) {
      $_->highlight (vaddd ($POS, 0, 0, $z), $time, [1, 1, 0]) for @pl;
   }

   $entity->{time_active} = 1;
   $entity->{tmp}->{rad} = $rad;
   $entity->{tmp}->{pos} = [@$POS];

}

sub ia_construction_pad {
   my ($PL, $POS) = @_;

   my $a = Games::Construder::World::get_pattern (@$POS, 0);
   if ($a) {
      my $obj = $Games::Construder::Server::RES->get_object_by_pattern ($a);
      if ($obj) {
         my ($score, $time) =
            $Games::Construder::Server::RES->get_type_construct_values ($obj->{type});

         if ($PL->{inv}->has_space_for ($obj->{type})) {
            my $a = Games::Construder::World::get_pattern (@$POS, 1);

            my @poses;
            while (@$a) {
               my $pos = [shift @$a, shift @$a, shift @$a];
               push @poses, $pos;
               $PL->highlight ($pos, $time, [0, 0, 1]);
            }

            world_mutate_at (\@poses, sub {
               my ($data) = @_;
               $data->[0] = 1;
               $data->[3] &= 0xF0; # clear color :)
               my $ent = $data->[5]; # kill entity
               $data->[5] = undef;
               if ($ent) {
                  Games::Construder::Server::Objects::destroy ($ent);
               }
               1
            }, no_light => 1);

            my $tmr;
            $tmr = AE::timer $time, 0, sub {
               world_mutate_at (\@poses, sub {
                  my ($data) = @_;
                  $data->[0] = 0;
                  1
               });

               my $gen_cnt = $obj->{model_cnt} || 1;

               my $cnt =
                  $obj->{permanent}
                     ? instance ($obj->{type})
                     : $gen_cnt;

               my $add_cnt =
                  $PL->{inv}->add ($obj->{type}, $cnt);
               if ($add_cnt > 0) {
                  $PL->push_tick_change (score => $score);
               }

               $PL->msg (0,
                  "Added $add_cnt of $gen_cnt $obj->{name} to your inventory."
                  . ($gen_cnt > $add_cnt ? " The rest was discarded." : ""));

               undef $tmr;
            };

         } else {
            $PL->msg (1, "The created $obj->{name} would not fit into your inventory!");
         }
      } else {
         $PL->msg (1, "Pattern not recognized!");
      }
   } else {
      $PL->msg (1, "No properly built construction floor found!");
   }
}

sub in_pattern_storage {
   {
   }
}

sub tmr_pattern_storage {
   my ($pos, $entity, $type, $dt) = @_;
}

sub ia_pattern_storage {
   my ($pl, $pos, $type, $entity) = @_;
   $pl->{uis}->{pattern_storage}->show ($pos, $entity);
}

sub in_message_beacon {
   {
      msg => "<unset message>"
   }
}

sub ia_message_beacon {
   my ($pl, $pos, $type, $entity) = @_;
   $pl->{uis}->{msg_beacon}->show ($pos, $entity);
}

sub in_teleporter {
   {
      msg => "<no destination>",
   }
}

sub ia_teleporter {
   my ($pl, $pos, $type, $entity) = @_;
   $pl->{uis}->{teleporter}->show ($pos);
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

