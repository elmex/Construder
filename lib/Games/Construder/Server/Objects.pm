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
package Games::Construder::Server::Objects;
use common::sense;
use Games::Construder::Server::PCB;
use Games::Construder::Server::World;
use Games::Construder::Vector;
use Games::Construder::Logging;
use Games::Construder;
use Scalar::Util qw/weaken/;

=head1 NAME

Games::Construder::Server::Objects - Implementation of Object Type specific behaviour

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
   51 => \&ia_auto,
   71 => \&ia_jumper,
   72 => \&ia_jumper,
   73 => \&ia_jumper,
   74 => \&ia_jumper,
);

our %TYPES_INSTANCIATE = (
   1  => \&in_materialization,
   31 => \&in_pattern_storage,
   34 => \&in_message_beacon,
   45 => \&in_vaporizer,
   46 => \&in_vaporizer,
   47 => \&in_vaporizer,
   48 => \&in_vaporizer,
   50 => \&in_drone,
   51 => \&in_auto,
   62 => \&in_teleporter,
   70 => \&in_mat_upgrade,
   71 => \&in_jumper,
   72 => \&in_jumper,
   73 => \&in_jumper,
   74 => \&in_jumper,
   500 => \&in_trophy,
   501 => \&in_trophy,
   502 => \&in_trophy,
   503 => \&in_trophy,
   504 => \&in_trophy,
   505 => \&in_trophy,
);

our %TYPES_TIMESENSITIVE = (
   1  => \&tmr_materialization,
   31 => \&tmr_pattern_storage,
   45 => \&tmr_vaporizer,
   46 => \&tmr_vaporizer,
   47 => \&tmr_vaporizer,
   48 => \&tmr_vaporizer,
   50 => \&tmr_drone,
   51 => \&tmr_auto,
   71 => \&tmr_jumper,
   72 => \&tmr_jumper,
   73 => \&tmr_jumper,
   74 => \&tmr_jumper,
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
   my ($type, @arg) = @_;

   my $cb = $TYPES_INSTANCIATE{$type}
      or return;
   my $i = $cb->($type, @arg);
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

sub in_trophy {
   {
      label => "ACME Inc.",
   }
}

sub in_mat_upgrade {
   { }
}

sub in_materialization {
   my ($type, $time, $end_action, %args) = @_;
   {
      time_active => 1,
      rest_time   => $time,
      action      => $end_action,
      %args
   }
}

sub tmr_materialization {
   my ($pos, $entity, $type, $dt) = @_;

   $entity->{rest_time} -= $dt;
   #d# warn "ENTITIY MAT DONE: " . JSON->new->pretty->encode ($entity) . "\n";

   return unless $entity->{rest_time} <= 0;

   my $handled = 0;
   if (my $act = $entity->{action}) {
      my ($pl) =
         $Games::Construder::Server::World::SRV->get_player ($entity->{player});
      my $mtype = $entity->{m_type};
      my $ment  = $entity->{m_type_ent};

      if ($act eq 'dematerialize') {
         my $unsuccessful = sub {
            world_mutate_at ($pos, sub {
               my ($d) = @_;
               if ($d->[0] == 1) {
                  $d->[0] = $mtype;
                  $d->[5] = $ment;
                  return 1;
               }
               0
            });
         };

         unless ($pl) {
            $unsuccessful->();
            return;
         }

         if ($pl->{inv}->add ($mtype, $ment || 1)) {
            world_mutate_at ($pos, sub {
               my ($d) = @_;
               if ($d->[0] == 1) {
                  $d->[0] = 0;
                  $d->[3] &= 0xF0;
                  return 1;
               }
               0
            });

         } else {
            $unsuccessful->();
         }

         $handled = 1;

      } elsif ($act eq 'materialize') {
         world_mutate_at ($pos, sub {
            my ($d) = @_;

            if ($d->[0] == 1) {
               $d->[0] = $mtype;
               $d->[5] = $ment;
               $d->[3] &= 0xF0; # clear color :)
               $d->[3] |= $entity->{color} & 0xF0;
               $pl->push_tick_change (score => $entity->{score}) if $pl;
               return 1
            }
            0
         });

         $handled = 1;
      }
   }

   unless ($handled) {
      world_mutate_at ($pos, sub {
         my ($d) = @_;
         if ($d->[0] == 1) {
            $d->[0] = 0;
            $d->[3] &= 0xF0;
            return 1;
         }
         return 0
      });
   }
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
         if ($d->[0] != 0) {
            $d->[0] = 0;
            $d->[3] &= 0xF0; # clear color :)
            return 1
         }
         0
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
      $_->[0]->highlight (vaddd ($POS, $x, 0, 0), $time, [1, 1, 0]) for @pl;
   }
   for my $y (-$rad..$rad) {
      $_->[0]->highlight (vaddd ($POS, 0, $y, 0), $time, [1, 1, 0]) for @pl;
   }
   for my $z (-$rad..$rad) {
      $_->[0]->highlight (vaddd ($POS, 0, 0, $z), $time, [1, 1, 0]) for @pl;
   }

   $entity->{time_active} = 1;
   $entity->{tmp}->{rad} = $rad;
   $entity->{tmp}->{pos} = [@$POS];

}

sub ia_construction_pad {
   my ($PL, $POS) = @_;

   my $a = Games::Construder::World::get_pattern (@$POS, 0);
   if ($a) {
      ctr_log (devel => "construction pad pattern at @$POS: %s", JSON->new->encode ($a));

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
               $data->[5] =
                  Games::Construder::Server::Objects::instance (
                     1, $time, 'disappear');
               1
            }, no_light => 1);

            my $tmr;
            $tmr = AE::timer $time, 0, sub {
               my $gen_cnt = $obj->{model_cnt} || 1; # || 1 shouldn't happen... but u never know

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
      inv => {
         ent => {},
         mat => {},
      },
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

sub in_drone {
   my ($type, $lifeticks, $teledist) = @_;
   {
      time_active   => 1,
      orig_lifetime => $lifeticks,
      lifetime      => $lifeticks,
      teleport_dist => $teledist,
   }
}

sub drone_kill {
   my ($pos, $entity) = @_;
   world_mutate_at ($pos, sub {
      my ($data) = @_;
      #d#warn "CHECK AT @$pos: $data->[0]\n";
      if ($data->[0] == 50) {
         warn "DRONE $entity DIED at @$pos\n";
         $data->[0] = 0;
         return 1;
      } else {
         warn "ERROR: DRONE $entity should have been at @$pos and dead. But couldn't find it!\n";
      }
      return 0;
   });
}

sub drone_visible_players {
   my ($pos, $entity) = @_;

   sort {
      $a->[1] <=> $b->[1]
   } grep {
      not $_->[0]->{data}->{signal_jammed}
   } $Games::Construder::Server::World::SRV->players_near_pos ($pos);
}

sub drone_check_player_hit {
   my ($pos, $entity, $pl) = @_;

   unless ($pl) {
      my (@pl) = drone_visible_players ($pos, $entity)
         or return;
      $pl = $pl[0]->[0];
   }

   if (vlength (vsub ($pl->{data}->{pos}, $pos)) <= 1.1) {
      my $dist = $entity->{teleport_dist} * 60;
      my ($new_pl_pos, $dist, $secdist) =
         world_find_random_teleport_destination_at_dist ($pl->{data}->{pos}, $dist);
      $dist = int $dist;
      $pl->teleport ($new_pl_pos);
      $pl->push_tick_change (happyness => -100);
      $pl->msg (1, "A Drone displaced you by $dist.");
      drone_kill ($pos, $entity);
   }
}

sub tmr_drone {
   my ($pos, $entity, $type, $dt) = @_;

   #d#warn "DRONE $entity LIFE $entity->{lifetime} from $entity->{orig_lifetime} at @$pos\n";
   $entity->{lifetime}--;
   if ($entity->{lifetime} <= 0) {
      drone_kill ($pos, $entity);
      return;
   }

   if ($entity->{in_transition}) {
      $entity->{transition_time} -= $dt;

      if ($entity->{transition_time} <= 0) {
         delete $entity->{in_transition};

         my $new_pos = $entity->{transistion_dest};
         world_mutate_at ($pos, sub {
            my ($data) = @_;

            if ($data->[0] == 50) {
               $data->[0] = 0;
               my $ent = $data->[5];
               $data->[5] = undef;

               world_mutate_at ($new_pos, sub {
                  my ($data) = @_;
                  $data->[0] = 50;
                  $data->[5] = $ent;
                  warn "drone $ent moved from @$pos to @$new_pos\n";
                  drone_check_player_hit ($new_pos, $ent);
                  return 1;
               });

               return 1;

            } else {
               warn "warning: drone $entity at @$pos is not where is hsould be, stopped!\n";
            }

            0
         }, need_entity => 1);
      } else {
         drone_check_player_hit ($pos, $entity);
      }

      return;
   }

   my (@pl) = drone_visible_players ($pos, $entity);

   return unless @pl;
   my $pl = $pl[0]->[0];
   my $new_pos = $pos;

   drone_check_player_hit ($pos, $entity, $pl);

   my $empty =
      Games::Construder::World::get_types_in_cube (
         @{vsubd ($new_pos, 1, 1, 1)}, 3, 0);

   my @empty;
   while (@$empty) {
      my ($pos, $type) = (
         [shift @$empty, shift @$empty, shift @$empty], shift @$empty
      );
      push @empty, $pos;
   }

   if (!@empty) {
      warn "debug: drone $entity is locked in (thats ok :)!\n";
      return;
   }

   my $min = [999999, $empty[0]];
   for my $dlt (
      [0, 0, 1],
      [0, 0, -1],
      [0, 1, 0],
      [0, -1, 0],
      [1, 0, 0],
      [-1, 0, 0]
   ) {
      my $np = vadd ($new_pos, $dlt);

      next unless grep {
         $_->[0] == $np->[0]
         && $_->[1] == $np->[1]
         && $_->[2] == $np->[2]
      } @empty;

      my $diff = vsub ($pl->{data}->{pos}, $np);
      my $dist = vlength ($diff);
      if ($min->[0] > $dist) {
         $min = [$dist, $np];
      }
   }

   $new_pos = $min->[1];

   my $lightness = $entity->{lifetime} / $entity->{orig_lifetime};

   $pl->highlight ($new_pos, 1.5 * $dt, [$lightness, $lightness, $lightness]);
   $entity->{in_transition} = 1;
   $entity->{transition_time} = 1.5 * $dt;
   $entity->{transistion_dest} = $new_pos;
   $pl->{uis}->{prox_warn}->show ("Proximity alert!\nDistance " . int ($min->[0]));
   if (delete $pl->{data}->{kill_drone}) {
      drone_kill ($pos, $entity);
      $pl->{uis}->{prox_warn}->show ("Drone killed!");
   }
}

sub in_auto {
   my ($type) = @_;

   {
      prog => { },
      used_energy => 0,
   }
}

sub ia_auto {
   my ($pl, $pos, $type, $entity) = @_;
   $pl->{uis}->{pcb_prog}->show ($entity);
}

our %DIR2VEC = (
   up       => [ 0,  1,  0],
   down     => [ 0, -1,  0],
   left     => [ 1,  0,  0],
   right    => [-1,  0,  0],
   forward  => [ 0,  0,  1],
   backward => [ 0,  0, -1],
);

sub tmr_auto {
   my ($pos, $entity, $type, $dt) = @_;

   warn "PCB @ @$pos doing something\n";

   my ($pl) = $Games::Construder::Server::World::SRV->get_player ($entity->{player})
      or return;

   my ($pcb_obj) =
      $Games::Construder::Server::RES->get_object_by_type ($type);

   my $pcb = Games::Construder::Server::PCB->new (p => $entity->{prog}, pl => $pl, act => sub {
      my ($op, @args) = @_;
      my $cb = pop @args;

      if ($op eq 'move') {
         my $dir = $DIR2VEC{$args[0]};
         my $new_pos = vadd ($pos, $dir);

         world_mutate_at ($new_pos, sub {
            my ($data) = @_;
            if ($data->[0] != 0) {
               my $obj = $Games::Construder::Server::RES->get_object_by_type ($data->[0]);
               $cb->($obj->{name});
               return 0;
            }

            world_mutate_at ($pos, sub {
               my ($data) = @_;
               if ($data->[0] == 51) {
                  $data->[0] = 0;
                  $data->[3] &= 0xF0; # clear color :)
                  return 1;
               }
               return 0;
            });

            $data->[0] = 51;
            $data->[3] &= 0xF0; # clear color :)
            $data->[5] = $entity;
            warn "pct $entity moved from @$pos to @$new_pos\n";
            $pos = $new_pos; # safety, so we are not moving from the same position again if the PCB code doesn't let the stepper wait...
            $cb->();
            return 1;
         });

      } elsif ($op eq 'vaporize') {
         my $dir = $DIR2VEC{$args[0]};
         my $new_pos = vadd ($pos, $dir);

         world_mutate_at ($new_pos, sub {
            my ($data) = @_;

            $entity->{used_energy} += 1;

            my ($obj) =
               $Games::Construder::Server::RES->get_object_by_type ($data->[0]);

            $data->[0] = 0;
            $data->[3] &= 0xF0; # clear color :)
            $pl->highlight ($new_pos, -$dt, [1, 1, 0]);
            $cb->($obj->{type} != 0 ? $obj->{name} : "");
            return 1;
         });

      } elsif ($op eq 'materialize') {
         my $dir = $DIR2VEC{$args[0]};
         my $new_pos = vadd ($pos, $dir);

         my ($obj) =
            $Games::Construder::Server::RES->get_object_by_name ($args[1]);
         unless ($obj) {
            $pl->msg (1, "PCB Error: No such material: '$args[1]'");
            $cb->("no_such_material");
            return;
         }

         warn "MATERIALIZE OBJECT: $obj | $obj->{type}\n";

         world_mutate_at ($new_pos, sub {
            my ($data) = @_;

            if ($data->[0] == 0) {
               my ($cnt, $ent) = $pl->{inv}->remove ($obj->{type});
               unless ($cnt) {
                  $cb->("empty");
                  return 0;
               }

               $data->[0] = $obj->{type};
               $data->[3] |= $args[2];
               $pl->highlight ($new_pos, $dt, [0, 1, 0]);

               my ($time, $energy, $score) =
                  $Games::Construder::Server::RES->get_type_materialize_values (
                     $obj->{type});

               $entity->{used_energy} += $energy;
               $score /= 10;
               $score = int $score;
               $pl->push_tick_change (score => $score);

               $cb->();
               return 1;

            } else {
               my $obj = $Games::Construder::Server::RES->get_object_by_type ($data->[0]);
               $cb->("blocked" => $obj->{name});
               return 0;
            }

         });

      } elsif ($op eq 'dematerialize') {
         my $dir = $DIR2VEC{$args[0]};
         my $new_pos = vadd ($pos, $dir);

         world_mutate_at ($new_pos, sub {
            my ($data) = @_;

            if ($data->[0] == 0) {
               $cb->("", "");
               return 0;
            }

            my ($obj) =
               $Games::Construder::Server::RES->get_object_by_type ($data->[0]);

            my ($time, $energy, $score) =
               $Games::Construder::Server::RES->get_type_dematerialize_values (
                  $obj->{type});

            if ($pl->{inv}->add ($data->[0], $data->[5] || 1)) {
               $pl->highlight ($new_pos, $dt, [1, 0, 0]);
               $data->[0] = 0;
               $data->[3] &= 0xF0;
               $data->[5] = undef;
               $entity->{used_energy} += $energy;
               $cb->("", $obj->{name});
               return 1;

            } else {
               $cb->("inv_full", $obj->{name});
               return 0;
            }
         }, need_entity => 1);

      } elsif ($op eq 'probe') {
         my $dir = $DIR2VEC{$args[0]};
         my $new_pos = vadd ($pos, $dir);

         world_mutate_at ($new_pos, sub {
            my ($data) = @_;

            if ($data->[0] == 0) {
               $cb->("");
               return 0;
            }

            my ($obj) =
               $Games::Construder::Server::RES->get_object_by_type ($data->[0]);
            $cb->($obj->{name});
            return 0;
         });

      } else {
         warn "DID $op (@args)!\n";
      }
   });

   warn "PCB @ @$pos doing somethingwith $pl->{name}\n";

   my $n = 10;
   while ($n-- > 0) {
      $pcb->{pos} = vfloor ($pos);
      $pcb->{energy_used} = $entity->{used_energy};
      $pcb->{energy_left} = ($pcb_obj->{energy} - $entity->{used_energy});
      my $cmd = $pcb->step ();
      warn "STEP COMMAND: $cmd\n";

      if ($cmd eq 'wait') {
         last;

      } elsif ($cmd eq 'done') {
         $entity->{time_active} = 0;
         last;

      } elsif ($cmd ne '') {
         $entity->{prog}->{wait} = 1;
         $pl->msg (1, "Program error with PCB at @$pos: $cmd");
      }
   }

   if ($pcb_obj->{energy} < $entity->{used_energy}) {
      $pl->msg (1, "PCB at @$pos ran out of energy and vaporized itself.");

      $pl->highlight ($pos, -$dt, [1, 1, 0]);
      world_mutate_at ($pos, sub {
         my ($data) = @_;
         if ($data->[0] == 51) {
            $data->[0] = 0;
            $data->[3] &= 0xF0; # clear color :)
            return 1;
         }
         return 0;
      });
   }
}

sub in_jumper {
   my ($type) = @_;
   my $obj =
      $Games::Construder::Server::RES->get_object_by_type ($type);
   {
      range       => $obj->{jumper_range},
      accuracy    => $obj->{jumper_accuracy},
      accuracy_vec => $obj->{jumper_accuracy_vec},
      fail_chance => $obj->{jumper_fail_chance},
      act_time    => 5,
   }
}

sub tmr_jumper {
   my ($pos, $entity, $type, $dt) = @_;

   unless ($entity->{did_hl}) {
      for ($Games::Construder::Server::World::SRV->players_near_pos ($pos)) {
         $_->[0]->highlight ($pos, $entity->{act_time}, [0, 1, 1]);
      }
      $entity->{did_hl} = 1;
   }

   $entity->{act_time} -= $dt;

   return if $entity->{act_time} > 0;

   world_mutate_at ($pos, sub {
      my ($d) = @_;

      if ($d->[0] == $type) {
         $d->[0] = 0;
         $d->[3] &= 0xF0;

         my ($pl) =
            $Games::Construder::Server::World::SRV->get_player ($entity->{player});
         return 1 unless $pl;

         if (rand () < $entity->{fail_chance}) {
            ctr_log (debug => "Jumper (failed) values: %s",
               JSON->new->encode ($entity));
            $pl->msg (1, "Jumper malfunction. Please retry.");
            return 1;
         }

         my $displ = $entity->{disp_vec};
         my $miss;

         if (rand () < $entity->{accuracy}) {
            my $len = vlength ($displ);
            $miss = [map {
               int (
                  ($entity->{accuracy} - rand ($entity->{accuracy} * 2))
                  * $len
                  + 0.5
               )
            } 0..2];
            $displ = vadd ($displ, $miss);
         }

         $pl->teleport (
            vadd ($pl->{data}->{pos}, vsmul ($displ, 60)),
            1
         );
         $pl->msg (0, "Jumper displaces you by @$displ sectors..."
                      . ($miss ? "Target missed by @$miss sectors..." : ""));

         ctr_log (debug => "Jumper (ok) values: %s, %s",
            JSON->new->encode ($entity), JSON->new->encode ($displ));

         return 1;
      }
      0
   });
}

sub ia_jumper {
   my ($PL, $POS, $type, $entity) = @_;
   $entity->{player} = $PL->{name};
   $PL->{uis}->{jumper}->show ($type, $entity);
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License.

=cut

1;

