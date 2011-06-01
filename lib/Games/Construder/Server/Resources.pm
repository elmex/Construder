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
}

sub load_region_file {
   my ($self) = @_;
   $self->{region_cmds} = _get_file ("res/region_noise.cmds");
}

sub load_objects {
   my ($self) = @_;
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
   if (defined $obj->{texture}) {
      $obj->{texture_id} =
         $self->load_texture ($obj->{texture});
   }
   $obj->{name} = $name;
   my $id = $self->add_res ({
      type => "object",
      data => {
         object_type => $obj->{type},
         texture_map => $obj->{texture_id},
         ($obj->{model} ? (model => $obj->{model}) : ()),
      }
   });

   print "Set object type $obj->{type}\n";
   Games::Construder::World::set_object_type (
      $obj->{type},
      ($obj->{type} == 0 || defined $obj->{model} ? 1 : 0),
      $obj->{type} != 0,
      0,0,0,0 # uv coors dont care!
   );

   $self->{object_res}->{$obj->{type}} = $obj;
}

sub get_object_by_type {
   my ($self, $typeid) = @_;
   $self->{object_res}->{$typeid}
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
      0, 1, 0, 0,
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

