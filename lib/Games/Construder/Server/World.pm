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
package Games::Construder::Server::World;
use common::sense;
use Games::Construder::Vector;
use Games::Construder;
use Time::HiRes qw/time/;
use Carp qw/confess/;
use Compress::LZF qw/decompress compress/;
use JSON;
use Storable qw/dclone/;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   world_init
   world_pos2id
   world_id2pos
   world_pos2chnkpos
   world_chnkpos2secpos
   world_secpos2chnkpos
   world_pos2relchnkpos
   world_mutate_at
   world_mutate_entity_at
   world_load_at
   world_find_free_spot
   world_at
   world_entity_at
   world_sector_info
   world_touch_sector
   world_load_at_player
   world_load_around_at
   world_save_all
/;


=head1 NAME

Games::Construder::Server::World - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

our $CHNK_SIZE = 12;
our $CHNKS_P_SEC = 5;

our $REGION_SEED = 42;
our $REGION_SIZE = 100; # 100x100x100 sections
our $REGION;

our %SECTORS;

our $STORE_SCHED_TMR;
our $FREE_TMR;
our $TICK_TMR;
our @SAVE_SECTORS_QUEUE;

our @LIGHTQUEUE;
our %LIGHTQUEUE;

our $SRV;

# neccessary so we can start other mutates
# from inside loading or mutate callbacks:
our $in_mutate;
our @mutate_cont;

sub world_init {
   my ($server, $region_cmds) = @_;

   $SRV = $server;

   Games::Construder::World::init (
      sub {
         my ($x, $y, $z) = @_;
         my $chnk = [$x, $y, $z];

         my $sec = world_chnkpos2secpos ($chnk);
         my $id  = world_pos2id ($sec);
         unless (exists $SECTORS{$id}) {
            # this might happen either due to bugs or when sectors are loaded
            # and light is calculated.
#            warn "updated sector which is not loaded "
#                 . "(chunk $x,$y,$z [@$sec]) $id. "
#                 . "but this should be okay :-)\n";
            return; # don't set dirty
         }
         world_sector_dirty ($sec);

         for (values %{$server->{players}}) {
            $_->chunk_updated ($chnk);
         }
      },
      sub {
         my ($x, $y, $z, $type, $ent) = @_;
         warn "ACTIVE CHANGE: $type ($x,$y,$z) ($ent)\n";
         my $sec = world_chnkpos2secpos (world_pos2chnkpos ([$x, $y, $z]));
         my $id  = world_pos2id ($sec);
         return unless exists $SECTORS{$id};
         my $eid = world_pos2id ([$x, $y, $z]);

         my $e = delete $SECTORS{$id}->{entities}->{$eid};
         if ($e) {
            warn "ENTITY $e DESTROY at sector $id ent $eid\n";
            Games::Construder::Server::Objects::destroy ($e);
         }

         unless ($ent) {
            $ent = Games::Construder::Server::Objects::instance ($type);
            warn "INSTANCE entity $eid at sector $id with type $type: $ent\n";
         } else {
            warn "PUT INSTANCED ENTITY $eid in sec $id with type $type: $ent\n";
         }
         $SECTORS{$id}->{entities}->{$eid} = $ent if $ent;
         warn "inst done\n";
      }
   );

   Games::Construder::VolDraw::init ();

   $STORE_SCHED_TMR = AE::timer 0, 1, sub {
      NEXT:
      my $s = shift @SAVE_SECTORS_QUEUE
         or return;
      return unless exists $SECTORS{$s->[0]};
      if ($SECTORS{$s->[0]}->{dirty}) {
         _world_save_sector ($s->[1]);
      } else {
         goto NEXT;
      }
   };

   $FREE_TMR = AE::timer 10, 5, sub {
      my (@invisible_sectors) = grep {
         my $s = $_;
         my $vis = 0;
         for (values %{$SRV->{players}}) {
            if ($_->{visible_sectors}->{$s}) {
               $vis = 1;
               last;
            }
         }
         not $vis
      } keys %SECTORS;

      for (@invisible_sectors) {
         warn "freeing invisible sector $_\n";
         world_free_sector ($_);
      }
      warn "SECTORS LOADED ON FREE: " . scalar (keys %SECTORS) . ": " . join (", ", keys %SECTORS) . "\n";
   };

   $TICK_TMR = AE::timer 0, 0.15, sub {
      for my $s (values %SECTORS) {
         for my $eid (keys %{$s->{entities}}) {
            my $e = $s->{entities}->{$eid};
            next unless $e->{time_active};
            my $pos = world_id2pos ($eid);
            Games::Construder::Server::Objects::tick ($pos, $e, $e->{type}, 0.15);
         }
      }

      $SRV->schedule_chunk_upd;

      _calc_some_lights ();
   };

   region_init ($region_cmds);
}

sub world_save_all {
   my ($self) = @_;
   for my $s (@SAVE_SECTORS_QUEUE) {
      return unless exists $SECTORS{$s->[0]};
      if ($SECTORS{$s->[0]}->{dirty}) {
         _world_save_sector ($s->[1]);
      }
   }
}

sub world_sector_dirty {
   my ($sec) = @_;
   my $id  = world_pos2id ($sec);
   return unless exists $SECTORS{$id};
   $SECTORS{$id}->{dirty} = 1;
   push @SAVE_SECTORS_QUEUE, [$id, $sec];
}

# still unused:
#sub world_touch_sector {
#   my ($self, $sec) = @_;
#   my $id = world_pos2id ($sec);
#   my $s = $SECTORS{$id}
#      or return;
#   $s->{last_touch} = time;
#}

sub world_free_sector {
   my ($id) = @_;
   my $sec = world_id2pos ($id);
   my $s = $SECTORS{$id}
      or return;
   if ($s->{dirty}) {
      _world_save_sector ($sec);
   }
   return if $s->{dirty};
   delete $SECTORS{$id};
   my $fchunk = world_secpos2chnkpos ($sec);
   for my $x (0..4) {
      for my $y (0..4) {
         for my $z (0..4) {
            Games::Construder::World::purge_chunk (
               $fchunk->[0] + $x,
               $fchunk->[1] + $y,
               $fchunk->[2] + $z
            );
         }
      }
   }
   warn "chunks from @$fchunk purged!\n";
}

my $light_upd_chunks_wait;

sub _calc_some_lights {
   my $alloced_time = 0.07;
   my $t1 = time;
   my $calced;

   {
      while ((time - $t1) < $alloced_time) {
         my $pos = shift @LIGHTQUEUE
            or last;
         delete $LIGHTQUEUE{world_pos2id ($pos)};
         my $secid = world_pos2id (world_chnkpos2secpos (world_pos2chnkpos ($pos)));
         unless (exists $SECTORS{$secid}) {
            next;
         }
         warn "calc light at @$pos\n";
         Games::Construder::World::flow_light_query_setup (@$pos, @$pos);
         Games::Construder::World::flow_light_at (@$pos);
         Games::Construder::World::query_desetup ();
         $calced++;
      }
   }
   if ($calced) {
      printf "calclight step %0.4f, calced %d lights, %d lights to go\n",
             time - $t1, $calced, scalar @LIGHTQUEUE;
   }
}

sub _query_push_lightqueue {
   my $lightposes = Games::Construder::World::query_search_types (35, 41, 41);
   while (@$lightposes) {
      my $pos = [shift @$lightposes, shift @$lightposes, shift @$lightposes];
      my $id = world_pos2id ($pos);
      unless ($LIGHTQUEUE{$id}) {
         $LIGHTQUEUE{$id} = 1;
         push @LIGHTQUEUE, $pos;
      }
   }
}

sub _world_make_sector {
   my ($sec) = @_;

   my $tcreate = time;

   my $val = Games::Construder::Region::get_sector_value ($REGION, @$sec);

   my ($stype, $param) =
      $Games::Construder::Server::RES->get_sector_desc_for_region_value ($val);

   my $seed = Games::Construder::Region::get_sector_seed (@$sec);

   warn "Create sector @$sec, with seed $seed value $val and "
        . "type $stype->{type} and param $param\n";

   my $cube = $CHNKS_P_SEC * $CHNK_SIZE;
   Games::Construder::VolDraw::alloc ($cube);

   Games::Construder::VolDraw::draw_commands (
     $stype->{cmds},
     { size => $cube, seed => $seed, param => $param }
   );

   Games::Construder::VolDraw::dst_to_world (@$sec, $stype->{ranges} || []);

   my $pospos = Games::Construder::World::query_possible_light_positions ();

   Games::Construder::World::query_desetup (1);

   my $lower_left  = vsmul ($sec, $CHNK_SIZE * $CHNKS_P_SEC);
   my $upper_right =
      vaddd ($lower_left,
             $CHNKS_P_SEC * $CHNK_SIZE,
             $CHNKS_P_SEC * $CHNK_SIZE,
             $CHNKS_P_SEC * $CHNK_SIZE);

   Games::Construder::World::flow_light_query_setup (@$lower_left, @$upper_right);

   my $t1 = time;

   my $plcnt = 0;
   my $tsum;
   my @poses;
   while (@$pospos) {
      push @poses,
         [shift @$pospos, shift @$pospos, shift @$pospos];
   }
   my $cnt = scalar @poses;
   my @types = qw/41 41 35/;
   my $rnd_type = Games::Construder::Random::rnd_xor ($seed);
   my $flot = Games::Construder::Random::rnd_float ($rnd_type) * 2.99999;
   my $type = $types[int $flot];

   my $nxt = $rnd_type;
   for (my $i = 0; $i < 50; $i++) {
      $nxt        = Games::Construder::Random::rnd_xor ($nxt);
      my $nxt_flt = Games::Construder::Random::rnd_float ($nxt) - 0.00000001;
      $nxt_flt    = 0 if $nxt_flt < 0;
      my $idx     = int ($nxt_flt * @poses);
#d# print "INDEX $nxt_flt | $idx from " . scalar (@poses) . "\n";

      my $p = splice @poses, $idx, 1, ();
      last unless $p;

      Games::Construder::World::query_set_at_abs (
         @$p, [$type, 0, 0, 0, 0]);
      $plcnt++;
   }

   _query_push_lightqueue ();
   $tsum += time - $t1;

   my $smeta = $SECTORS{world_pos2id ($sec)} = {
      created    => time,
      pos        => [@$sec],
      region_val => $val,
      seed       => $seed,
      param      => $param,
      light_type => $type,
      light_cnt  => $cnt,
      creation_time => (time - $tcreate),
      type       => $stype->{type},
      entities   => { },
   };
   _world_save_sector ($sec);
   warn "created sector @$sec in $smeta->{creation_time} seconds\n";

   {
      Games::Construder::World::query_desetup (2);
   }

   warn "PLACED $cnt / $plcnt lights $type ($flot) in $tsum!\n";
}

sub _world_load_sector {
   my ($sec) = @_;

   my $t1 = time;

   my $id   = world_pos2id ($sec);
   my $mpd  = $Games::Construder::Server::Resources::MAPDIR;
   my $file = "$mpd/$id.sec";

   return 1 if ($SECTORS{$id}
                && !$SECTORS{$id}->{broken});

   unless (-e $file) {
      return 0;
   }

   if (open my $mf, "<", "$file") {
      binmode $mf, ":raw";
      my $cont = eval { decompress (do { local $/; <$mf> }) };
      if ($@) {
         warn "map sector data corrupted '$file': $@\n";
         return -1;
      }

      warn "read " . length ($cont) . "bytes\n";

      my ($metadata, $mapdata, $data) = split /\n\n\n*/, $cont, 3;
      unless ($mapdata =~ /MAPDATA/) {
         warn "map sector file '$file' corrupted! Can't find 'MAPDATA'. "
              . "Please delete or move it away!\n";
         return -1;
      }

      my ($md, $datalen, @lens) = split /\s+/, $mapdata;
      #d#warn "F $md, $datalen, @lens\n";
      unless (length ($data) == $datalen) {
         warn "map sector file '$file' corrupted, sector data truncated, "
              . "expected $datalen bytes, but only got ".length ($data)."!\n";
         return -1;
      }

      my $meta = eval { JSON->new->relaxed->utf8->decode ($metadata) };
      if ($@) {
         warn "map sector meta data corrupted '$file': $@\n";
         return -1;
      }

      $SECTORS{$id} = $meta;
      $meta->{load_time} = time;

      {
         my $offs;
         my $first_chnk = world_secpos2chnkpos ($sec);
         my @chunks;
         for my $dx (0..($CHNKS_P_SEC - 1)) {
            for my $dy (0..($CHNKS_P_SEC - 1)) {
               for my $dz (0..($CHNKS_P_SEC - 1)) {
                  my $chnk = vaddd ($first_chnk, $dx, $dy, $dz);

                  my $len = shift @lens;
                  my $chunk = substr $data, $offs, $len;
                  Games::Construder::World::set_chunk_data (
                     @$chnk, $chunk, length ($chunk));
                  $offs += $len;
               }
            }
         }

         my $lower_left  = vsmul ($sec, $CHNK_SIZE * $CHNKS_P_SEC);
         my $upper_right =
            vaddd ($lower_left,
                   $CHNKS_P_SEC * $CHNK_SIZE,
                   $CHNKS_P_SEC * $CHNK_SIZE,
                   $CHNKS_P_SEC * $CHNK_SIZE);

         Games::Construder::World::flow_light_query_setup (@$lower_left, @$upper_right);
         _query_push_lightqueue ();
         Games::Construder::World::query_desetup (2);
      }


      my ($ecnt) = scalar (keys %{$SECTORS{$id}->{entities}});

      delete $SECTORS{$id}->{dirty}; # saved with the sector
      warn "loaded sector $id from '$file', got $ecnt entities, took "
           . sprintf ("%.3f seconds", time - $t1)
           . ".\n";

      return 1;

   } else {
      warn "couldn't open map sector '$file': $!\n";
      return -1;
   }
}

sub _world_save_sector {
   my ($sec) = @_;

   my $t1 = time;

   my $id   = world_pos2id ($sec);
   my $meta = $SECTORS{$id};

   if ($meta->{broken}) {
      warn "map sector '$id' marked as broken, won't save!\n";
      return;
   }

   $meta->{save_time} = time;

   my $first_chnk = world_secpos2chnkpos ($sec);
   my @chunks;
   for my $dx (0..($CHNKS_P_SEC - 1)) {
      for my $dy (0..($CHNKS_P_SEC - 1)) {
         for my $dz (0..($CHNKS_P_SEC - 1)) {
            my $chnk = vaddd ($first_chnk, $dx, $dy, $dz);
            push @chunks,
               Games::Construder::World::get_chunk_data (@$chnk);
         }
      }
   }

   my ($ecnt) = scalar (keys %{$SECTORS{$id}->{entities}});

   $meta = dclone ($meta);
   for (values %{$meta->{entities}}) {
      $_->{tmp} = {}; # don't store entity temporary data (might contain objects)
   }
   my $meta_data = JSON->new->utf8->pretty->encode ($meta || {});

   my $data = join "", @chunks;
   my $filedata = compress (
      $meta_data . "\n\nMAPDATA "
      . join (' ', map { length $_ } ($data, @chunks))
      . "\n\n" . $data
   );

   my $mpd = $Games::Construder::Server::Resources::MAPDIR;
   my $file = "$mpd/$id.sec";

   if (open my $mf, ">", "$file~") {
      binmode $mf, ":raw";
      print $mf $filedata;
      close $mf;
      unless (-s "$file~" == length ($filedata)) {
         warn "couldn't save sector completely to '$file~': $!\n";
         return;
      }

      if (rename "$file~", $file) {
         delete $SECTORS{$id}->{dirty};
         warn "saved sector $id to '$file', saved $ecnt entities, took "
              . sprintf ("%.3f seconds", time - $t1)
              . "wrote " . length($filedata) . " bytes\n";

      } else {
         warn "couldn't rename '$file~' to '$file': $!\n";
      }

   } else {
      warn "couldn't save sector $id to '$file~': $!\n";
   }
}

sub region_init {
   my ($cmds) = @_;

   my $t1 = time;

   warn "calculating region, with seed $REGION_SEED.\n";
   Games::Construder::VolDraw::alloc ($REGION_SIZE);

   Games::Construder::VolDraw::draw_commands (
     $cmds,
     { size => $REGION_SIZE, seed => $REGION_SEED, param => 1 }
   );

   $REGION = Games::Construder::Region::new_from_vol_draw_dst ();
   warn "done, took " . (time - $t1) . " seconds.\n";
}

sub world_sector_info_at {
   world_sector_info (world_pos2chnkpos ($_[0]))
}

sub world_sector_info {
   my ($chnk) = @_;
   my $sec = world_chnkpos2secpos ($chnk);
   my $id  = world_pos2id ($sec);
   unless (exists $SECTORS{$id}) {
      return undef;
   }
   $SECTORS{$id}
}

sub world_pos2id {
   my ($pos) = @_;
   join "x", map { $_ < 0 ? "N" . abs ($_) : $_ } @{vfloor ($pos)};
}

sub world_id2pos {
   my ($id) = @_;
   [map { s/^N/-/; $_ } split /x/, $id]
}

sub world_pos2chnkpos {
   vfloor (vsdiv ($_[0], $CHNK_SIZE))
}

sub world_chnkpos2secpos {
   vfloor (vsdiv ($_[0], $CHNKS_P_SEC))
}

sub world_secpos2chnkpos {
   vsmul ($_[0], $CHNKS_P_SEC);
}

sub world_pos2relchnkpos {
   my ($pos) = @_;
   my $chnk = world_pos2chnkpos ($pos);
   vsub ($pos, vsmul ($chnk, $CHNK_SIZE))
}

sub world_load_at_player {
   my ($pl, $cb) = @_;

   my $cnt = scalar keys %{$pl->{visible_sectors}};
   for (keys %{$pl->{visible_sectors}}) {
#d#warn "VISIBLESEC $_\n";
      unless ($SECTORS{$_}) {
         world_load_sector (world_id2pos ($_), sub {
            $cnt--;
            $cb->() if $cnt <= 0;
         });
      } else {
         $cnt--;
         $cb->() if $cnt <= 0;
#d#     warn "SECTOR $_ IS THERE!\n";
      }
   }
}

sub world_load_around_at {
   my ($pos, $cb) = @_;

   my $chnk = world_pos2chnkpos ($pos);
   my $cnt = 3 ** 3;
   for my $x (-2, 0, 2) {
      for my $y (-2, 0, 2) {
         for my $z (-2, 0, 2) {
            my $ch = vaddd ($chnk, $x, $y, $z);
            world_load_at_chunk ($ch, sub {
               if (--$cnt <= 0) {
                  $cb->();
               }
            });
         }
      }
   }
}

sub world_load_at {
   my ($pos, $cb) = @_;
   world_load_at_chunk (world_pos2chnkpos ($pos), $cb);
}

sub world_load_at_chunk {
   my ($chnk, $cb) = @_;
   my $sec = world_chnkpos2secpos ($chnk);
   world_load_sector ($sec, $cb);
}

sub world_load_sector {
   my ($sec, $cb) = @_;

   if ($in_mutate) {
      push @mutate_cont, sub { world_load_sector ($sec, $cb); };
      return;
   }

   local $in_mutate = 1;

   my $secid = world_pos2id ($sec);
   unless ($SECTORS{$secid}) {
      warn "LOAD SECTOR $secid\n";
      my $r = _world_load_sector ($sec);
      if ($r == 0) {
         _world_make_sector ($sec);
      }
   }
   $cb->() if $cb;

   warn "SECTORS LOADED: " . scalar (keys %SECTORS) . ": "
                           . join (", ", keys %SECTORS) . " \n";

   local $in_mutate = 0;

   while (@mutate_cont) {
      my $m = shift @mutate_cont;
      $m->();
   }
}

sub world_entity_at {
   my ($pos) = @_;
   my $si = world_sector_info_at ($pos)
      or return;
   my $eid = world_pos2id ($pos);
   $si->{entities}->{$eid}
}

sub world_at {
   my ($poses, $cb, %arg) = @_;

   world_mutate_at ($poses, sub {
      my ($cell, $pos) = @_;
      push @$cell, world_entity_at ($pos);
      $cb->($pos, $cell);
      return 0;
   }, need_entity => 1, %arg);
}

sub world_mutate_entity_at {
   my ($pos, $cb, %arg) = @_;

   world_mutate_at ($pos, sub {
      my ($cell, $pos) = @_;
      my $si = world_sector_info_at ($pos);
      push @$cell, world_entity_at ($pos);
      if ($cb->($pos, $cell)) {
         world_sector_dirty ($si->{pos});
      }
      return 0;
   }, need_entity => 1, %arg);
}

sub world_mutate_at {
   my ($poses, $cb, %arg) = @_;

   if ($in_mutate) {
      push @mutate_cont, sub { world_mutate_at ($poses, $cb, %arg); };
      return,
   }

   local $in_mutate = 1;

   if (ref $poses->[0]) {
      my $min = [];
      my $max = [];
      for (@$poses) {
         $min->[0] = $_->[0] if !defined $min->[0] || $min->[0] > $_->[0];
         $min->[1] = $_->[1] if !defined $min->[1] || $min->[1] > $_->[1];
         $min->[2] = $_->[2] if !defined $min->[2] || $min->[2] > $_->[2];
         $max->[0] = $_->[0] if !defined $max->[0] || $max->[0] < $_->[0];
         $max->[1] = $_->[1] if !defined $max->[1] || $max->[1] < $_->[1];
         $max->[2] = $_->[2] if !defined $max->[2] || $max->[2] < $_->[2];
      }

      my $chnk_x = int ((($max->[0] - $min->[0]) / $CHNK_SIZE) + 0.5);
      my $chnk_y = int ((($max->[1] - $min->[1]) / $CHNK_SIZE) + 0.5);
      my $chnk_z = int ((($max->[2] - $min->[2]) / $CHNK_SIZE) + 0.5);
      my $base_chnk = world_pos2chnkpos ($min);

      for (my $x = $base_chnk->[0]; $x < $base_chnk->[0] + $chnk_x; $x++) {
         for (my $y = $base_chnk->[1]; $y < $base_chnk->[1] + $chnk_y; $y++) {
            for (my $z = $base_chnk->[2]; $z < $base_chnk->[2] + $chnk_z; $z++) {
               world_load_at_chunk ([$x, $y, $z]);
            }
         }
      }
     #d# warn "MUTL @$min | @$max\n";
      Games::Construder::World::flow_light_query_setup (@$min, @$max);

   } else {
      world_load_at ($poses); # blocks for now :-/

      Games::Construder::World::flow_light_query_setup (@$poses, @$poses);
      $poses = [$poses];
   }

   for my $pos (@$poses) {
      my $b = Games::Construder::World::at (@$pos);
      my $ent;
      $ent = world_entity_at ($pos) if $arg{need_entity};
      push @$b, $ent;
      #d# print "MULT MUTATING (@$b) (AT @$pos)\n";
      if ($cb->($b, $pos)) {
         #d# print "MULT MUTATING TO => (@$b) (AT @$pos)\n";
         Games::Construder::World::query_set_at_abs (@$pos, $b);
         unless ($arg{no_light}) {
            my $t1 = time;
            Games::Construder::World::flow_light_at (@{vfloor ($pos)});
            printf "mult light calc took: %f\n", time - $t1;
         }
      }
   }

   {
      Games::Construder::World::query_desetup ();
   }

   local $in_mutate = 0;

   while (@mutate_cont) {
      my $m = shift @mutate_cont;
      $m->();
   }
}

sub world_find_free_spot {
   my ($pos, $wflo) = @_;
   $wflo = 0 unless defined $wflo;
   Games::Construder::World::find_free_spot (@$pos, $wflo);
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

