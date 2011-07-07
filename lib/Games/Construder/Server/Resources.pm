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
package Games::Construder::Server::Resources;
use common::sense;
use AnyEvent;
use JSON;
use Digest::MD5 qw/md5_base64/;
use Games::Construder::Server::Objects;
use File::ShareDir::PAR;
use Storable qw/dclone/;
use base qw/Object::Event/;

=head1 NAME

Games::Construder::Server::Resources - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Construder::Server::Resources->new (%args)

=cut

our $VARDIR = $ENV{HOME}    ? "$ENV{HOME}/.construder"
            : $ENV{AppData} ? "$ENV{APPDATA}/construder"
            : File::Spec->tmpdir . "/construder";

our $PLAYERDIR = "$VARDIR/players";
our $MAPDIR    = "$VARDIR/chunks";

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;

   return $self
}

sub init_directories {
   my ($self) = @_;

   unless (-e $VARDIR && -d $VARDIR) {
      mkdir $VARDIR
         or die "Couldn't create var data dir '$VARDIR': $!\n";
   }

   unless (-e $PLAYERDIR && -d $PLAYERDIR) {
      mkdir $PLAYERDIR
         or die "Couldn't create player data dir '$PLAYERDIR': $!\n";
   }

   unless (-e $MAPDIR && -d $MAPDIR) {
      mkdir $MAPDIR
         or die "Couldn't create map data dir '$MAPDIR': $!\n";
   }
}

sub _get_file {
   my ($file) = @_;
   open my $f, "<", $file
      or die "Couldn't open '$file': $!\n";
   binmode $f, ":raw";
   do { local $/; <$f> }
}

sub _get_shared_file {
   my ($file) = @_;
   _get_file (File::ShareDir::PAR::dist_file ('Games-Construder', $file))
}

sub load_content_file {
   my ($self) = @_;
   $self->{content} =
      JSON->new->relaxed->utf8->decode (my $f = _get_shared_file ("content.json"));

   my $stypes = $self->{content}->{sector_types}
     or die "No sector types defined in content.json!\n";
   for (keys %$stypes) {
      $stypes->{$_}->{type} = $_;
      $stypes->{$_}->{cmds} = _get_shared_file ("$stypes->{$_}->{file}");
   }

   my $atypes = $self->{content}->{assign_types};
   for (keys %$atypes) {
      $atypes->{$_}->{type} = $_;
      $atypes->{$_}->{cmds} = _get_shared_file ("$atypes->{$_}->{file}");
   }

   my $music = $self->{content}->{music};
   $self->{music} = {};
   for (keys %$music) {
      $self->load_music ($_, $music->{$_});
   }

   $self->{region_cmds} =
      _get_shared_file ("$self->{content}->{region}->{file}");

   $self->load_text_db;
}

sub construct_ship_query {
   my ($self) = @_;
   my $shpdb = $self->{txt_db}->{ship};
   #d#print "TEXT TREE FROM: " . JSON->new->pretty->encode ($shpdb) . "\n";

   my %nodes;

   for (keys %$shpdb) {
      my $con = delete $shpdb->{$_}->{content};
      my ($l, $r) = split /\n/, $con, 2;
      $nodes{$_} = {
         title => $l,
         text  => $r,
      };
   }

   for my $k (keys %$shpdb) {
      for (keys %{$shpdb->{$k}}) {
         push @{$nodes{$k}->{childs}}, [
            $shpdb->{$k}->{$_},
            $nodes{$_}
         ];
      }
   }

   #d#print "TEXT TREE: " . JSON->new->pretty->encode (\%nodes) . "\n";
   $self->{ship_tree} = \%nodes;
}

sub get_ship_tree_at {
   my ($self, $key) = @_;
   $self->{ship_tree}->{$key}
}

sub load_text_db {
   my ($self) = @_;
   my $txt = _get_shared_file ("$self->{content}->{text_db}->{file}");
   my $db = {};

   my @records = split /\r?\n\.\r?\n/, $txt;

   for (@records) {
      if (/^((?::[^\r\n]+\s*\r?\n)+)\s*(.*)$/s) {
         my $keys = $1;

         my $txt = $2;
         $txt =~ s/(?<!\n)\r?\n/ /sg;

         for my $k (split /\r?\n/, $keys) {
            my ($dummy, @keys) = split /:/, $k;
            my $last = pop @keys;
            my $d = $db;
            for (@keys) {
               $d = $d->{$_} ||= {};
            }
            $d->{$last} .= $txt;
         }
      }
   }

   $self->{txt_db} = $db;

   $self->construct_ship_query;
}

sub load_objects {
   my ($self) = @_;
   my $objects = $self->{content}->{types};
   $self->load_object ($_, $objects->{$_}) for keys %$objects;
   $self->loaded_objects;
}

sub add_res {
   my ($self, $res) = @_;

   $self->{res_ids}++;
   $self->{resources}->[$self->{res_ids}] = $res;
   $res->{id} = $self->{res_ids};
   $res->{id}
}

sub load_texture_file {
   my ($self, $file) = @_;

   my $tex;
   unless ($self->{texture_data}->{$file}) {
      my $data = _get_shared_file ("$file");
      my $md5  = md5_base64 ($tex->{data});
      my $rid = $self->add_res ({
         type => "texture",
         data => $data,
         md5  => $md5
      });

      $self->{texture_data}->{$file} = $rid;
      warn "loaded texture $file: $self->{res_ids} $md5 " . length ($data) . "\n";
   }

   $self->{texture_data}->{$file}
}

sub load_object {
   my ($self, $name, $obj) = @_;

   if (my $txt = $self->{txt_db}->{obj}->{$name}) {
      $obj->{$_} = $txt->{$_} for keys %$txt;
   }

   if (defined $obj->{texture}) {
      $obj->{texture_id} =
         $self->load_texture ($obj->{texture});
   }
   if ($obj->{model}) {
      $obj->{model_str} = join ',', @{$obj->{model}};
   }
   $obj->{name} = $name;
   my $id = $self->add_res ({
      type => "object",
      data => {
         object_type => $obj->{type},
         ($obj->{texture} ? (texture_map => $obj->{texture_id}) : ()),
         ($obj->{model} ? (model => $obj->{model}) : ()),
      }
   });

   my $isact =
      exists $Games::Construder::Server::Objects::TYPES_INSTANCIATE{$obj->{type}};

   print "Set object type $obj->{type}: $isact\n";
   Games::Construder::World::set_object_type (
      $obj->{type},
      ($obj->{type} == 0 || (!$obj->{texture}  && defined $obj->{model} ? 1 : 0)),
      $obj->{type} != 0,
      $obj->{texture},
      $isact,
      0,0,0,0 # uv coors dont care!
   );

   $self->{object_res}->{$obj->{type}} = $obj;
}

sub get_object_by_name {
   my ($self, $name) = @_;

   grep {
      $name eq $_->{name}
   } values %{$self->{object_res}};
}

sub get_object_by_type {
   my ($self, $typeid) = @_;
   $typeid != 0
      ? $self->{object_res}->{$typeid}
      : { untransformable => 1, buildable => 1 }
}

sub load_texture {
   my ($self, $texture_def) = @_;

   my $file = ref $texture_def ? $texture_def->[0] : $texture_def;
   my $tex_id = $self->load_texture_file ($file);

   my $txtres_id = $self->add_res ({
      type => "texture_mapping",
      data => {
         tex_id => $tex_id,
         (ref $texture_def
            ? (uv_map => [map { $texture_def->[$_] } 1..4])
            : ())
      }
   });
   $txtres_id
}

sub load_music {
   my ($self, $name, $mentry) = @_;

   $self->{music}->{$name} = $mentry;

   my $data  = _get_shared_file ("music/" . $mentry->{file});

   my $md5  = md5_base64 ($data);
   $self->{music}->{$name}->{res}
      = $self->add_res ({
         type => "music",
         data => $data,
         md5  => $md5,
      });
}

sub list_resources {
   my ($self) = @_;

   my $res = [];

   for (@{$self->{resources}}) {
      push @$res, [
         $_->{id},
         $_->{type},
         $_->{md5},
         (ref $_->{data} ? $_->{data} : ())
      ];
   }

   $res
}

sub get_resources_by_id {
   my ($self, @ids) = @_;
   [
      map {
         my $res = $self->{resources}->[$_];
         [ $_, $res->{type}, $res->{md5}, \$res->{data} ]
      } @ids
   ]
}

sub loaded_objects : event_cb {
   my ($self) = @_;

   Games::Construder::World::set_object_type (
      0, 1, 0, 0, 0, 0,
      0, 0, 0
   );

   $self->calc_object_levels;
}

sub get_random_assignment {
   my ($self) = @_;
   my @atypes = keys %{$self->{content}->{assign_types}};
   my $at = $atypes[int (rand (@atypes))];
   $self->{content}->{assign_types}->{$at}
}

sub get_sector_types {
   my ($self) = @_;
   my @sec;

   my $stypes = $self->{content}->{sector_types};
   for (sort keys %$stypes) {
      push @sec, [$_, @{$stypes->{$_}->{region_range}}];
   }

   @sec
}

sub get_sector_desc_for_region_value {
   my ($self, $val) = @_;
   my $stypes = $self->{content}->{sector_types};
   for (keys %$stypes) {
      my $s = $stypes->{$_};
      my ($a, $b) = @{$s->{region_range}};

      if ($val >= $a && $val < $b) {
         my $r = $b - $a;
         return ($s, ($r > 0 ? ($val - $a) / $r : 1));
      }
   }

   return ();
}

sub get_type_source_materials {
   my ($self, $type) = @_;
   my $o = $self->get_object_by_type ($type);

   my %out;

   my (@model) = @{$o->{model} || []}
      or return ();
   shift @model; # dimension
   while (@model) {
      shift @model;
      my $t = shift @model;
      $out{$t}++;
   }

   map {
      my $o = $self->get_object_by_type ($_);
      [$o, $out{$_}]
   } keys %out
}

sub get_types_where_type_is_source_material {
   my ($self, $type) = @_;

   my @dest;

   for my $o (values %{$self->{object_res}}) {
      my (@model) = @{$o->{model} || []}
         or next;
      shift @model; # dimension
      while (@model) {
         shift @model;
         if ((shift @model) == $type) {
            unless (grep { $_ eq $o } @dest) {
               push @dest, $o;
            }
         }
      }
   }

   sort { $a->{name} cmp $b->{name} } @dest
}

sub calc_object_levels {
   my ($self) = @_;

   my $objects = $self->{object_res};

   my $change = 1;
   my $pass = 1;
   while ($change) {
      $change = 0;
      print "Pass $pass\n";
      $pass++;
      for my $o (sort { $a->{level} <=> $b->{level} } values %$objects) {
         unless (defined $o->{level}) {
            my (@sub) = $self->get_sector_types_where_type_is_found ($o->{type});
            if (@sub) {
               $o->{level} = 1;
               $o->{natural} = 1;
            } elsif (!$o->{model} || $o->{model_cnt} == 0) {
               $o->{level} = 9999999;
            }
            $change = 1;
         }

         my (@smat) = $self->get_type_source_materials ($o->{type});
         my $level = 0;
         for (@smat) {
            $_->[0]->{useful} = 1;
            $level += $_->[0]->{level} * $_->[1];
         }
         if ($level > $o->{level}) {
            $o->{level} = $level;
            $change = 1;
         }
         printf "%-20s: %3d %s\n", $o->{name}, $o->{level}, $o->{useful} ? "useful" : "";
      }
   }

   $self->{objects_by_level} = {};
   $self->{max_object_level} = 0;

   for my $o (values %$objects) {
      push @{$self->{objects_by_level}->{$o->{level}}}, $o;
      if ($o->{level} != 9999999 && $o->{level} > $self->{max_object_level}) {
         $self->{max_object_level} = $o->{level};
      }
   }
}

sub get_handbook_types {
   my ($self) = @_;
   map {
      $self->{object_res}->{$_}
   } grep {
      $self->{object_res}->{$_}->{level} < 9999999
   } keys %{$self->{object_res}}
}

sub get_sector_types_where_type_is_found {
   my ($self, $type) = @_;

   my $stypes = $self->{content}->{sector_types};
   my @out;

   for my $stype (keys %$stypes) {
      my $st = $stypes->{$stype};
      my (@rng) = @{$st->{ranges}};
      my @types;
      while (@rng) {
         shift @rng;
         shift @rng;
         push @types, shift @rng;
      }

      if (grep { $_ == $type } @types) {
         push @out, $stype;
      }
   }

   sort { $a cmp $b } @out
}

sub get_object_by_pattern {
   my ($self, $pattern) = @_;
   my ($dim, @a) = @$pattern;
   my @pat;
   while (@a) {
      my ($nr, $type) = (shift @a, shift @a);
      $pat[$nr] = $type;
   }

   my $matrix = [];
   my $blk = 1;
   for (my $y = 0; $y < $dim; $y++) {
      for (my $z = 0; $z < $dim; $z++) {
         for (my $x = 0; $x < $dim; $x++) {
            $matrix->[$x]->[$y]->[$z] = $pat[$blk];
            $blk++;
         }
      }
   }

   my @collection;

   my $di = $dim - 1;

   for my $it (
      [0, [0..$di], 1, [0..$di]],
      [0, [0..$di], 1, [reverse (0..$di)]],
      [0, [reverse (0..$di)], 1, [0..$di]],
      [0, [reverse (0..$di)], 1, [reverse (0..$di)]],
      [1, [0..$di], 0, [0..$di]],
      [1, [0..$di], 0, [reverse (0..$di)]],
      [1, [reverse (0..$di)], 0, [0..$di]],
      [1, [reverse (0..$di)], 0, [reverse (0..$di)]],
   ) {
      my ($idx1, $range1, $idx2, $range2) = @$it;
      my @idx;
      my $p = [];


      my $blk = 0;
      for (my $y = 0; $y < $dim; $y++) {

         for my $i1 (@$range1) {
            $idx[$idx1] = $i1;

            for my $i2 (@$range2) {
               $idx[$idx2] = $i2;
#print "TEST $idx1 $idx2 | $idx[0] $idx[1]\n";

               if (my $t = $matrix->[$idx[1]]->[$y]->[$idx[0]]) {
                  $p->[$blk] = $t;
               }

               $blk++;
            }
         }
      }

      push @collection, $p;
   }

   my @str_coll;
   for my $pat (@collection) {
      my @pat;
      for (my $i = 0; $i < $dim ** 3; $i++) {
         push @pat, $i + 1, $pat->[$i] if $pat->[$i] ne '';
      }
      push @str_coll, join ",", $dim, @pat;
   }

   warn "Patterns: " . join ("\n", @str_coll) . "\n";

   for my $o (values %{$self->{object_res}}) {
      next if $o->{model_cnt} == 0;
      warn "SEARCH $o->{type} || $o->{model_str} <=>\n" . join (",\n", @str_coll) . "\n";
      if (grep { $o->{model_str} eq $_ } @str_coll) {
         warn "Found Model $o->{model_str}! => $o->{type}\n";
         return $o;
      }
   }

   undef
}

sub lerp {
   my ($a, $b, $x) = @_;
   $a * (1 - $x) + $b * $x
}

sub get_initial_inventory {
   my ($self) = @_;
   dclone $self->{content}->{initial_inventory}
}

sub get_inventory_max_dens {
   my ($self) = @_;
   $self->{content}->{balancing}->{max_inventory_density}
}

sub get_type_dematerialize_values {
   my ($self, $type, $upgrade) = @_;

   my $bal = $self->{content}->{balancing};
   my $max_time   = $bal->{max_dematerialize_time};
   my $max_energy = $bal->{max_dematerialize_bio};

   my $obj = $self->get_object_by_type ($type);
   $obj or return (1, 1);

   my $cplx = $obj->{complexity} / 100;
   my $dens = $obj->{density} / 100;
   my ($time, $energy);

   if ($dens < 0.5) {
      $time = ($dens / 2) * $max_time;
   } else {
      $time = ($dens ** 2) * $max_time;
   }

   if ($upgrade) {
      $time /= 10;
      $cplx = lerp ($cplx, 1, 0.5);
   }

   if ($cplx < 0.5) {
      $energy = ($cplx / 2) * $max_energy;
   } else {
      $energy = ($cplx ** 2) * $max_energy;
   }

   $energy = int ($energy + 0.5);
   $energy = 1 if $energy < 1;

   warn "dematerialize($type): $time / $energy\n";

   ($time, $energy)
}

sub _cplx_dens_2_score {
   my ($self, $cplx, $dens) = @_;

   my $bal       = $self->{content}->{balancing};
   my $max_score = $bal->{max_materialize_score};

   $cplx = $cplx ** 1.5; # exponential spread of complexity

   # complexity determines majority of score
   my $score = int ($max_score * $cplx);
   my $diff = $max_score - $score;

   # rest of score difference is determined by the density
   # the higher the difference is, the more the density is taken into account
   my $rem = $diff * ($dens * (1 - ($diff / $max_score)));
   $score += $rem;

   # round up score to a nice value:
   $score = int (($score / 10) + 0.5) * 10;

   $score
}

sub get_type_materialize_values {
   my ($self, $type, $upgrade) = @_;

   my $bal = $self->{content}->{balancing};
   my $max_time   = $bal->{max_materialize_time};
   my $max_energy = $bal->{max_materialize_bio};
   my $max_score  = $bal->{max_materialize_score};

   my $obj = $self->get_object_by_type ($type);
   $obj or return (1, 1, 0);

   my $cplx = $obj->{complexity} / 100;
   my $dens = $obj->{density} / 100;
   my ($time, $energy);
   if ($dens < 0.5) {
      $time = ($dens / 2) * $max_time;
   } else {
      $time = ($dens ** 2) * $max_time;
   }

   if ($upgrade) {
      $time /= 10;
      $cplx = lerp ($cplx, 1, 0.5);
   }

   if ($cplx < 0.5) {
      $energy = ($cplx / 2) * $max_energy;
   } else {
      $energy = ($cplx ** 2) * $max_energy;
   }

   $energy = int ($energy + 0.5);

   my $score = $self->_cplx_dens_2_score ($cplx, $dens);

   $energy = 1    if $energy < 1;
   $time   = 0.05 if $time < 0.05;;

   warn "materialize($type): $time / $energy / $score\n";

   ($time, $energy, $score)
}

sub get_type_construct_values {
   my ($self, $type) = @_;

   my $obj       = $self->get_object_by_type ($type);
   my $bal       = $self->{content}->{balancing};
   my $max_score = $bal->{max_construction_score};
   my $max_time  = $bal->{max_construction_clear_time};

   my $time = ($obj->{density} / 100) * $max_time;

   my $max_fact      = 4 * (100/100);
   my $type_dim_fact = $obj->{model}->[0] + 1;
   my $cplx          = ($obj->{complexity} / 100) * $type_dim_fact;
   my $score         = $max_score * ($cplx / $max_fact);

   # round up score to a nice value:
   $score = int (($score / 10) + 0.5) * 10;
   $time  = 0.05 if $time < 0.05;;

   ($score, $time)
}

sub get_assignment_for_score {
   my ($self, $score, $diff) = @_;

   $diff ||= 1;

   my ($desc, $size, $material_map, $distance, $time);

   my $abal          = $self->{content}->{balancing}->{assignments};
   my $max_ass_score = $abal->{max_score};

   $score = $abal->{min_score} if $score < $abal->{min_score};

   # some random extra score, he might earn (also raises level):
   my $bonus_score = lerp (0, 0.005, rand ()) * $max_ass_score;
   $score += $bonus_score;
   $score += ($max_ass_score * $diff) * 0.01;

   # "difficulty" level of assignment:
   my $level = $score / $max_ass_score;
   warn "SCORE $score | max $max_ass_score => $level\n";
   $level = 1 if $level > 1;

   # create shape:
   $desc = $self->get_random_assignment;
   $desc = $desc->{cmds};

   # size:
   $size = int (lerp ($abal->{min_size}, $abal->{max_size}, $level));

   # select materials:
   my $mat_level = int (lerp (1, $self->{max_object_level}, $level)); # material level
   my $mat_num   = int (lerp (1, 7,   $level)); # different materials


   # calculate materials:
   my @materials;
   my $avg_mat_lvl;
   for (my $i = 0; $i < $mat_num; $i++){
      my $max;
      my (@matlvl) = sort {
         $b <=> $a
      } grep {
         $_ <= $mat_level
      } keys %{$self->{objects_by_level}};

      unless (@matlvl) {
         warn "no material with level suitable for level $mat_level found!\n";
      }
      $avg_mat_lvl += $matlvl[0];
      my (@os) = @{$self->{objects_by_level}->{$matlvl[0]}};
      my $mat = $os[int (rand (@os))];
      push @materials, $mat;

      $mat_level = $matlvl[0] - 1;
      $mat_level = 1 if $mat_level <= 0;
   }

   $avg_mat_lvl /= $mat_num;
   # calc time based on materials and size
   $time +=
      ($size ** 3)
      * lerp (0.5, 1, $avg_mat_lvl / $self->{max_object_level})
      * $abal->{time_per_block};

   my $material_map = [];
   my $interv = 1 / @materials;
   my $low = 0.0001;
   for (@materials) {
      push @$material_map,
         [ $low, $low + $interv, $_->{type} ];
      $low += $interv;
   }
   $material_map->[-1]->[1] += 0.0001;

   warn "time after material: $time\n";
   # calculate distance of assignment
   $distance = lerp ($abal->{min_distance}, $abal->{max_distance}, $level);
   $time += $distance * $abal->{time_per_pos};
   $distance *= 60;
   warn "time after distance: $time\n";

   # include the time factor for high levels
   my $time_fact = lerp (1, $abal->{max_score_time_fact}, $level);
   $time *= $time_fact;
   $time = int $time;
   warn "time after factor $time_fact: $time\n";

   my $ascore = lerp ($abal->{min_score}, $abal->{max_score}, $level);
   $ascore = int (($ascore / 50) + 0.5) * 50;

   ($desc, $size, $material_map, $distance, $time, $ascore)
}

sub score2happyness {
   my ($self, $score) = @_;
   my $bal     = $self->{content}->{balancing};
   my $s_per_h = $bal->{score_per_happyness};

   my $s = $score / $s_per_h;

   $s
}

sub player_values {
   my ($self) = @_;
   $self->{content}->{balancing}->{player};
}

sub encounter_values {
   my ($self) = @_;
   my $enc = $self->{content}->{balancing}->{encounters};
   my $tele_dist =
      lerp ($enc->{teleport_min_dist}, $enc->{teleport_max_dist}, rand ());
   my $time_to_next =
      60 * lerp ($enc->{time_min_next}, $enc->{time_max_next}, rand ());
   my $lifetime =
      lerp ($enc->{lifetime_min}, $enc->{lifetime_max}, rand ());

   ($tele_dist, $time_to_next, $lifetime)
}

sub _trophy_of {
   my ($self, $old, $new, $score, $time) = @_;
   my @trophies;
   my $diff = $new - $old;
   my $n  = int ($old / $score);
   my $n2 = int ($new / $score);
   for (my $i = $n; $i <= $n2; $i++) {
      push @trophies, [$i * $score, $time];
   }
   @trophies
}

sub generate_trophies_for_score_change {
   my ($self, $old, $new, $time) = @_;
   my @trohpies;

   my $t1h   = 100;
   my $t1k   = 1000;
   my $t10k  = 10000;
   my $t100k = 100000;
   my $t1m   = 1000000;
   my $t10m  = 10000000;

   for ($t1h, $t1k, $t10k, $t100k, $t1m, $t10m) {
      if ($new < (10 * $_)) {
         push @trohpies, $self->_trophy_of ($old, $new, $_, $time);
         last;
      }
   }

   @trohpies
}

sub get_trophy_type_by_score {
   my ($self, $score) = @_;

   my $t1h   = 100;
   my $t1k   = 1000;
   my $t10k  = 10000;
   my $t100k = 100000;
   my $t1m   = 1000000;
   my $t10m  = 10000000;

   my $s;
   for ($t1h, $t1k, $t10k, $t100k, $t1m, $t10m) {
      if ($score < (10 * $_)) {
         $s = $_;
         last;
      }
   }

   my $trophyt = 504; # default :)

   for my $t (keys %{$self->{object_res}}) {
      if ($self->{object_res}->{$t}->{trophy_score} == $s) {
         $trophyt = $t;
      }
   }

   $trophyt
}

sub credits {
   my ($self) = @_;
   $self->{content}->{credits}
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

