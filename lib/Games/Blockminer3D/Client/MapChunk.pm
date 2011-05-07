package Games::Blockminer3D::Client::MapChunk;
use common::sense;
use Time::HiRes qw/time/;
use OpenGL qw/:all/;
use Games::Blockminer3D::Vector;

use base qw/Object::Event/;

=head1 NAME

Games::Blockminer3D::Client::MapChunk - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

A chunk of the Blockminer3D world.

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Client::MapChunk->new (%args)

=cut

our $SIZE = 12;
our $BSPHERE = sqrt (3 * (($SIZE/2) ** 2));

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;

   return $self
}

sub _map_get_if_exists {
   my ($map, $x, $y, $z) = @_;
   return [0, 16, 1, 0, 1] if $x < 0     || $y < 0     || $z < 0;
   return [0, 16, 1, 0, 1] if $x >= $SIZE || $y >= $SIZE || $z >= $SIZE;
   #$map->[$x + ($y + $z * $SIZE) * $SIZE]
   $map->[$x]->[$y]->[$z]# + ($y + $z * $SIZE) * $SIZE]
}

sub _neighbours {
   my ($map, $x, $y, $z) = @_;
 #  my ($cur, $top, $bot, $left, $right, $front, $back) 
   (
      _map_get_if_exists ($map, $x, $y,     $z),
      _map_get_if_exists ($map, $x, $y + 1, $z),
      _map_get_if_exists ($map, $x, $y - 1, $z),
      _map_get_if_exists ($map, $x - 1, $y, $z),
      _map_get_if_exists ($map, $x + 1, $y, $z),
      _map_get_if_exists ($map, $x, $y,     $z - 1),
      _map_get_if_exists ($map, $x, $y,     $z + 1),
   )
}

sub _data2array {
   my ($dat) = @_;
   my ($blk, $meta, $add) = unpack "nCC", $dat;
   my ($type, $light) = (($blk & 0xFFF0) >> 4, ($blk & 0x000F));
   [$type, $light, $meta, $add]
}

sub data_fill {
   my ($self, $res, $data) = @_;

   my $t1 = time;
   my $map = [];
   for (my $z = 0; $z < $SIZE; $z++) {
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $x = 0; $x < $SIZE; $x++) {
            my $chnk_offs = $x + $y * $SIZE + $z * ($SIZE ** 2);
            my $c = $map->[$x]->[$y]->[$z] = _data2array (substr $data, $chnk_offs * 4, 4);
            $c->[2] = 1;
            my ($txtid, $surf, $uv, $model) = $res->obj2texture ($c->[0]);
            if ($c->[0] == 0 || $model) { $c->[4] = 1; }

            #d#warn "DATAFILL: $x,$y,$z: " . JSON->new->encode ($map->[$x]->[$y]->[$z]) . "\n";
         }
      }
   }

   $self->{map} = $map;
   return;

   my $visible;
   for (my $z = 0; $z < $SIZE; $z++) {
      for (my $y = 0; $y < $SIZE; $y++) {
         for (my $x = 0; $x < $SIZE; $x++) {
            my ($cur, $top, $bot, $left, $right, $front, $back)
               = _neighbours ($map, $x, $y, $z);
            my $cnt = 0;
            $cnt++ if $top->[0]   == 0 || $top->[4];
            $cnt++ if $bot->[0]   == 0 || $bot->[4];
            $cnt++ if $left->[0]  == 0 || $left->[4];
            $cnt++ if $right->[0] == 0 || $right->[4];
            $cnt++ if $front->[0] == 0 || $front->[4];
            $cnt++ if $back->[0]  == 0 || $back->[4];

            if ($cnt == 0
                && not (
                   $x == 0 || $x == $SIZE - 1
                   || $y == 0 || $y == $SIZE - 1
                   || $z == 0 || $z == $SIZE - 1)
            ) {
               $cur->[2] = 0;
            } else {
               $cur->[2] = 1;
               $visible++;
            }
         }
      }
   }
   $self->visible_quads;

   warn "VISIBLE: $visible : ".(time - $t1)."\n";
   $self->{map} = $map;
}

sub chunk_changed : event_cb {
   my ($self) = @_;
   delete $self->{quads_cache};
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

