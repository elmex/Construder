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
   36 => \&ia_construction_pad,
   45 => \&ia_vaporizer,
);

our %TYPES_INSTANCIATE = (
   31 => \&in_pattern_storage,
   45 => \&in_vaporizer,
);

our %TYPES_TIMESENSITIVE = (
   31 => \&tmr_pattern_storage,
   45 => \&tmr_vaporizer,
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
   {
      time_active => 1,
      time => 4,
   }
}

sub tmr_vaporizer {
   my ($pos, $entity, $type, $dt) = @_;
   warn "vapo tick: $dt\n";
   my (@pl) =
      $Games::Construder::Server::World::SRV->players_near_pos ($pos);
   warn "palyersnear: @pl\n";
}

sub ia_vaporizer {
   my ($PL, $POS) = @_;
   my $where = {};

   my (@pl) =
      $Games::Construder::Server::World::SRV->players_near_pos ($POS);

   my $rad = 10;

   for my $x (-$rad..$rad) {
      $_->highlight (vaddd ($POS, $x, 0, 0), 2, [1, 1, 0]) for @pl;
   }
   for my $y (-$rad..$rad) {
      $_->highlight (vaddd ($POS, 0, $y, 0), 2, [1, 1, 0]) for @pl;
   }
   for my $z (-$rad..$rad) {
      $_->highlight (vaddd ($POS, 0, 0, $z), 2, [1, 1, 0]) for @pl;
   }

   my @poses;
   for my $x (-$rad..$rad) {
      for my $y (-$rad..$rad) {
         for my $z (-$rad..$rad) {
            push @poses, my $p = vaddd ($POS, $x, $y, $z);
         }
      }
   }

   $where->{tout} = AE::timer 2, 0, sub {
      world_mutate_at (\@poses, sub {
         my ($d) = @_;
         $d->[0] = 0;
         1
      });
      undef $where;
   };
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

               my $add_cnt =
                  $PL->{inv}->add ($obj->{type}, instance ($obj->{type}) || $gen_cnt);
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

