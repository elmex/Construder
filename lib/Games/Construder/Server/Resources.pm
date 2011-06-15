package Games::Construder::Server::Resources;
use common::sense;
use AnyEvent;
use JSON;
use Digest::MD5 qw/md5_base64/;
use base qw/Object::Event/;

=head1 NAME

Games::Construder::Server::Resources - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Construder::Server::Resources->new (%args)

=cut

our $VARDIR = $ENV{HOME}    ? "$ENV{HOME}/.blockminer3d"
            : $ENV{AppData} ? "$ENV{APPDATA}/blockminer3d"
            : File::Spec->tmpdir . "/blockminer3d";

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

sub load_world_gen_file {
   my ($self) = @_;
   $self->{world_gen} = JSON->new->relaxed->decode (my $f = _get_file ("res/world_gen.json"));

   my $stypes = $self->{world_gen}->{sector_types}
     or die "No sector types defined in world_gen.json!\n";
   for (keys %$stypes) {
      $stypes->{$_}->{type} = $_;
      $stypes->{$_}->{cmds} = _get_file ("res/$stypes->{$_}->{file}");
   }

   my $music = $self->{world_gen}->{music};
   $self->{music} = {};
   for (keys %$music) {
      $self->load_music ($_, $music->{$_});
   }
}

sub load_region_file {
   my ($self) = @_;
   $self->{region_cmds} = _get_file ("res/region_noise.cmds");
}

sub load_text_db {
   my ($self) = @_;
   my $txt = _get_file ("res/text.db");
   my $db = {};

   my @records = split /\r?\n\r?\n/, $txt;

   for (@records) {
      if (/^(\S+)\s*\n(.*)$/s) {
         my $txt = $2;
         my (@keys) = split /:/, $1;
         my $last = pop @keys;
         my $d = $db;
         for (@keys) {
            $d = $d->{$_} ||= {};
         }
         $txt =~ s/\r?\n/ /sg;
         $d->{$last} = $txt;
      }
   }

   $self->{txt_db} = $db;
}

sub load_objects {
   my ($self) = @_;
   $self->load_text_db;

   my $objects = JSON->new->relaxed->decode (_get_file ("res/objects/types.json"));
   $self->{objects} = $objects;

   for (keys %$objects) {
      my $ob = $objects->{$_};
      $self->load_object ($_, $objects->{$_});
   }

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
      my $data = _get_file ("res/objects/" . $file);
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

   print "Set object type $obj->{type}\n";
   Games::Construder::World::set_object_type (
      $obj->{type},
      ($obj->{type} == 0 || (!$obj->{texture}  && defined $obj->{model} ? 1 : 0)),
      $obj->{type} != 0,
      $obj->{texture},
      0,0,0,0 # uv coors dont care!
   );

   $self->{object_res}->{$obj->{type}} = $obj;
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

   my $data  = _get_file ("res/music/" . $mentry->{file});

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
      0, 1, 0, 0, 0,
      0, 0, 0
   );

   print "loadded objects:\n" . JSON->new->pretty->encode ($self->{objects}) . "\n";
}

sub get_sector_types {
   my ($self) = @_;
   my @sec;

   my $stypes = $self->{world_gen}->{sector_types};
   for (sort keys %$stypes) {
      push @sec, [$_, @{$stypes->{$_}->{region_range}}];
   }

   @sec
}

sub get_sector_desc_for_region_value {
   my ($self, $val) = @_;
   my $stypes = $self->{world_gen}->{sector_types};
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

sub get_sector_types_where_type_is_found {
   my ($self, $type) = @_;

   my $stypes = $self->{world_gen}->{sector_types};
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
# z 0-3 * x 0-3
#   x 0 1 2 3
# z
# 0   X Y
# 1       Z
# 2         L
# 3   A

# x 0-3 * z 3-0
#   x 0 1 2 3
# z
# 0       L
# 1     Z
# 2   Y
# 3   X     A

# z 3-0 * x 3-0
#   x 0 1 2 3
# z
# 0         A
# 1   L
# 2     Z
# 3       Y X

# x 3-0 * z 3-0
#   x 0 1 2 3
# z
# 0   A     X
# 1         Y
# 2       Z
# 3     L
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
      warn "SEARCH $o->{model_str} <=> @str_coll\n";
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
   my $inv = $self->{world_gen}->{initial_inventory};
   my $i = {};
   (%$i) = (%$inv);
   $i
}

sub get_type_inventory_space {
   my ($self, $type) = @_;

   my $bal = $self->{world_gen}->{balancing};
   my $max_carry = $bal->{max_inventory_space_per_type};
   my $min_carry = $bal->{min_inventory_space_per_type};

   my $obj = $self->get_object_by_type ($type);
   $obj or return 0;

   my $dens = $obj->{density} / 100;

   my $space = int (lerp ($min_carry, $max_carry, (1 - $dens)));
   warn "invspace: $type => $dens | $space\n";
   $space
}

sub get_type_dematerialize_values {
   my ($self, $type) = @_;

   my $bal = $self->{world_gen}->{balancing};
   my $max_time   = $bal->{max_dematerialize_time};
   my $max_energy = $bal->{max_dematerialize_bio};

   my $obj = $self->get_object_by_type ($type);
   $obj or return (1, 1);

   my $cplx = $obj->{complexity} / 100;
   my $dens = $obj->{density} / 100;
   my ($time, $energy);
   if ($dens < 50) {
      $time = ($dens / 2) * $max_time;
   } else {
      $time = ($dens ** 2) * $max_time;
   }

   if ($cplx < 50) {
      $energy = ($dens / 2) * $max_energy;
   } else {
      $energy = ($dens ** 2) * $max_energy;
   }

   $energy = int ($energy + 0.5);
   $energy = 1 if $energy < 1;

   warn "dematerialize($type): $time / $energy\n";

   ($time, $energy)
}

sub _cplx_dens_2_score {
   my ($self, $cplx, $dens) = @_;

   my $bal       = $self->{world_gen}->{balancing};
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
   my ($self, $type) = @_;

   my $bal = $self->{world_gen}->{balancing};
   my $max_time   = $bal->{max_materialize_time};
   my $max_energy = $bal->{max_materialize_bio};
   my $max_score  = $bal->{max_materialize_score};

   my $obj = $self->get_object_by_type ($type);
   $obj or return (1, 1, 0);

   my $cplx = $obj->{complexity} / 100;
   my $dens = $obj->{density} / 100;
   my ($time, $energy);
   if ($dens < 50) {
      $time = ($dens / 2) * $max_time;
   } else {
      $time = ($dens ** 2) * $max_time;
   }

   if ($cplx < 50) {
      $energy = ($dens / 2) * $max_energy;
   } else {
      $energy = ($dens ** 2) * $max_energy;
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
   my $bal       = $self->{world_gen}->{balancing};
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

sub score2happyness {
   my ($self, $score) = @_;
   my $bal     = $self->{world_gen}->{balancing};
   my $s_per_h = $bal->{score_per_happyness};

   my $s = $score / $s_per_h;

   $s
}

sub player_values {
   my ($self) = @_;
   $self->{world_gen}->{balancing}->{player};
}


=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 SEE ALSO

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

