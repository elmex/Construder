package Games::Blockminer3D::Server::ChunkManager;
use common::sense;
use Games::Blockminer3D::Server::World;
use Games::Blockminer3D::Vector;
use JSON;
use AnyEvent::Util;
use Time::HiRes qw/time/;

=head1 NAME

Games::Blockminer3D::Server::ChunkManager - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Server::ChunkManager->new (%args)

=cut

our $CHUNKS_P_SECTOR = 5;

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   return $self
}

sub check_adjacent_sectors_at {
   my ($self, $pos) = @_;
   my $chnk = world_pos2chnkpos ($pos);

   for my $dx (-2, 0, 2) {
      for my $dy (-2, 0, 2) {
         for my $dz (-2, 0, 2) {
            my $sec   = world_chnkpos2secpos (vaddd ($chnk, $dx, $dy, $dz));
            my $secid = world_pos2id ($sec);
            unless ($self->{sector}->{$secid}) {
               warn "LOAD SECTOR $secid\n";
               $self->load_sector ($sec);
            }
         }
      }
   }

}

sub load_sector {
   my ($self, $sec) = @_;

   my $chnk = world_secpos2chnkpos ($sec);
   Games::Blockminer3D::World::query_setup (
      $chnk->[0],
      $chnk->[1],
      $chnk->[2],
      $chnk->[0] + ($CHUNKS_P_SECTOR - 1),
      $chnk->[1] + ($CHUNKS_P_SECTOR - 1),
      $chnk->[2] + ($CHUNKS_P_SECTOR - 1)
   );
   Games::Blockminer3D::World::query_load_chunks ();

   my $center = [12 * 2, 12 * 2, 12 * 2];

   my @types = (2..8);
   for my $x (0..(12 * 5 - 1)) {
      for my $y (0..(12 * 5 - 1)) {
         for my $z (0..(12 * 5 - 1)) {

            my $cur = [$x, $y, $z];
            my $l = vlength (vsub ($cur, $center));
            if ($x == 36 || $y == 36 || $z == 36 || ($l > 20 && $l < 21)) {
               my $t = [13, int rand (16)];
               Games::Blockminer3D::World::query_set_at (
                  $x, $y, $z, $t
               );
            } else {
               Games::Blockminer3D::World::query_set_at (
                  $x, $y, $z,
                  [(rand (1000) > 990 ? 90 : 0),int rand (16)]
               );
            }
         }
      }
   }

   Games::Blockminer3D::World::query_desetup ();

   $self->{sector}->{world_pos2id ($sec)} = 1;
}

sub chunk_changed {
   my ($self, $x, $y, $z) = @_;
   my $id = world_pos2id ([$x, $y, $z]);
   $self->{chunk_meta}->{$id}->{dirty} = 1;
}

sub load_chunk {
   my ($self, $x, $y, $z) = @_;

   my $id   = world_pos2id ([$x, $y, $z]);
   my $mpd  = $Games::Blockminer3D::Server::Resources::MAPDIR;
   my $file = "$mpd/$id.chunk";

   return 1 if ($self->{chunk_meta}->{$id}
                && !$self->{chunk_meta}->{$id}->{broken});

   unless (-e $file) {
      return 0;
   }

   if (open my $mf, "<", "$file") {
      binmode $mf, ":raw";
      my $cont = do { local $/; <$mf> };

      if ($cont =~ /^(.+?)\n\nMAPDATA (\d+)\n\n(.+)$/s) {
         my ($metadata, $data) = ($1, $3);

         unless (length ($3) == $2) {
            warn "map chunk file '$file' corrupted, chunk data truncated!\n";
            return -1;
         }

         my $meta = eval { JSON->new->relaxed->utf8->decode ($metadata) };
         if ($@) {
            warn "map chunk meta data corrupted '$file': $@\n";
            return -1;
         }

         $self->{chunk_meta}->{$id} = $meta;
         $meta->{load_time} = time;

         Games::Blockminer3D::World::set_chunk_data (
            $x, $y, $z, $data, length ($data));
         warn "loaded chunk $id from '$file'.\n";

      } else {
         warn "map chunk file '$file' corrupted! Please delete or move it away!\n";
         return -1;
      }
   } else {
      warn "couldn't open map chunk '$file': $!\n";
      return -1;
   }

}

sub save_chunk {
   my ($self, $x, $y, $z) = @_;

   my $id   = world_pos2id ([$x, $y, $z]);
   my $meta = $self->{chunk_meta}->{$id};

   if ($meta->{broken}) {
      warn "map chunk '$id' marked as broken, won't save!\n";
      return;
   }

   $meta->{save_time} = time;

   my $data = Games::Blockminer3D::World::get_chunk_data ($x, $y, $z);
   my $meta_data = JSON->new->utf8->pretty->encode ($meta || {});

   my $filedata = $meta_data . "\n\nMAPDATA " . length ($data) . "\n\n" . $data;

   my $mpd = $Games::Blockminer3D::Server::Resources::MAPDIR;
   my $file = "$mpd/$id.chunk";

   if (open my $mf, ">", "$file~") {
      binmode $mf, ":raw";
      print $mf $filedata;
      close $mf;
      unless (-s "$file~" == length ($filedata)) {
         warn "couldn't save chunk completely to '$file~': $!\n";
         return;
      }

      if (rename "$file~", $file) {
         delete $self->{chunk_meta}->{$id}->{dirty};
         warn "saved chunk $id to '$file'.\n";

      } else {
         warn "couldn't rename '$file~' to '$file': $!\n";
      }

   } else {
      warn "couldn't save chunk $id to '$file~': $!\n";
   }
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

