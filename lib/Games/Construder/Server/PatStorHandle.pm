package Games::Construder::Server::PatStorHandle;
use common::sense;
use base qw/Object::Event/;

=head1 NAME

Games::Construder::Server::PatStorHandle - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Construder::Server::PatStorHandle->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->{data}->{inv}->{mat} ||= {};
   $self->{data}->{inv}->{ent} ||= {};

   return $self
}

sub split_invid {
   my ($self, $id) = @_;
   unless (ref $self) {
      $id = $self;
   }

   my ($type, $i) = split /:/, $id, 2;
   if ($i ne '') {
      return ($type, $id)
   } else {
      return ($type, $type)
   }
}

sub free_slots {
   my ($self) = @_;
   my $mat = $self->{data}->{inv}->{mat};
   my $ent = $self->{data}->{inv}->{ent};
   my $mat_type_cnt =
      scalar (grep { $_ ne '' && $_ != 0 } keys %$mat);
   my $ent_cnt = scalar keys %$ent;
   my $sum = $mat_type_cnt + $ent_cnt;
   $self->{slot_cnt} < $sum
      ? 0 : $self->{slot_cnt} - $sum
}

sub space_for {
   my ($self, $type) = @_;

   my ($max_spc, $perm) = $Games::Construder::Server::RES->get_type_inventory_space ($type);
   my $fslots = $self->free_slots;
   warn "SPACEFOR $max_spc | $perm: $type\n";

   if ($perm) {
      return ($fslots, $fslots)

   } else {
      my $cnt;
      if (exists $self->{data}->{inv}->{mat}->{$type}) {
         $cnt = $self->{data}->{inv}->{mat}->{$type};
      } else {
         if ($fslots > 0) {
            $cnt = $max_spc;
         }
      }
      my $dlta = $max_spc - $cnt;
      ($dlta < 0 ? 0 : $dlta, $max_spc)
   }
}

sub has_space_for {
   my ($self, $type, $cnt) = @_;
   $cnt ||= 1;
   my ($spc, $max) = $self->space_for ($type);
   $spc >= $cnt
}

sub add {
   my ($self, $type, $cnt) = @_;

   my ($spc, $max) = $self->space_for ($type);

   if (ref $cnt) { # permanent entity
      return 0 if $spc <= 0;

      my $invid = $type . ":" . $cnt;
      $self->{data}->{inv}->{ent}->{$invid} = $cnt;
      $cnt = 1;

   } else {
      return 0 if $spc <= 0;

      $cnt ||= 1;
      $cnt = $spc if $spc < $cnt;
      $self->{data}->{inv}->{mat}->{$type} += $cnt;
   }

   $self->changed;

   $cnt
}

sub remove {
   my ($self, $type, $cnt) = @_;

   $cnt ||= 1;

   my $old_val = 0;

   if ($type eq 'all') {
      $self->{data}->{inv}->{mat} = {};
      $self->{data}->{inv}->{ent} = {};
      $self->changed;
      return ();
   }

   my $ent;

   if ($type =~ /:/) {
      $ent = delete $self->{data}->{inv}->{ent}->{$type};
      $old_val = 1 if $ent;

   } else {
      $old_val = $self->{data}->{inv}->{mat}->{$type};
      $self->{data}->{inv}->{mat}->{$type} -= $cnt;
      if ($self->{data}->{inv}->{mat}->{$type} <= 0) {
         delete $self->{data}->{inv}->{mat}->{$type};
      }
   }

   $self->changed;

   ($old_val > 0, $ent)
}

sub get_invids {
   my ($self) = @_;
   sort { $a <=> $b } (keys %{$self->{data}->{inv}->{mat}}, keys %{$self->{data}->{inv}->{ent}})
}

sub get_count { # should be renamed to count() and also count permanent types even without direct $invid
   my ($self, $invid) = @_;

   if ($invid =~ /:/) {
      my $ent = $self->{data}->{inv}->{ent}->{$invid};
      if ($ent) {
         return (1, 1);
      } else {
         return ();
      }
   } else {
      my ($spc, $max) = $self->space_for ($invid);
      my $cnt = $self->{data}->{inv}->{mat}->{$invid};
      return ($cnt, $max);
   }
}

sub max_bio_energy_material {
   my ($self) = @_;

   my (@max_e) = sort {
      $b->[1] <=> $a->[1]
   } grep { $_->[1] } map {
      my $obj = $Games::Construder::Server::RES->get_object_by_type ($_);
      [$_, $obj->{bio_energy}]
   } keys %{$self->{data}->{inv}->{mat}};

   @max_e ? $max_e[0] : ()
}

sub changed : event_cb {
   my ($self) = @_;
}

#sub inventory_space_for {
#   my ($self, $type) = @_;
#   my $spc = $Games::Construder::Server::RES->get_type_inventory_space ($type);
#   my $cnt;
#   if (exists $self->{data}->{inv}->{$type}) {
#      $cnt = $self->{data}->{inv}->{$type};
#   } else {
#      if (scalar (grep { $_ ne '' && $_ != 0 } keys %{$self->{data}->{inv}}) >= $PL_MAX_INV) {
#         $cnt = $spc;
#      }
#   }
#
#   my $dlta = $spc - $cnt;
#
#   ($dlta < 0 ? 0 : $dlta, $spc)
#}
#
#sub has_inventory_space {
#   my ($self, $type, $cnt) = @_;
#   $cnt ||= 1;
#   my ($spc, $max) = $self->inventory_space_for ($type);
#   $spc >= $cnt
#}
#
#sub increase_inventory {
#   my ($self, $type, $cnt) = @_;
#
#   $cnt ||= 1;
#
#   my ($spc, $max) = $self->inventory_space_for ($type);
#   if ($spc > 0) {
#      $cnt = $spc if $spc < $cnt;
#      $self->{data}->{inv}->{$type} += $cnt;
#
#      if ($self->{uis}->{inventory}->{shown}) {
#         $self->{uis}->{inventory}->show; # update if neccesary
#      }
#
#      $self->{uis}->{slots}->show;
#
#      return $cnt;
#   }
#   0
#}
#
#sub decrease_inventory {
#   my ($self, $type, $cnt) = @_;
#
#   $cnt ||= 1;
#
#   my $old_val = 0;
#
#   if ($type eq 'all') {
#      $self->{data}->{inv} = {};
#
#   } else {
#      $old_val = $self->{data}->{inv}->{$type};
#      $self->{data}->{inv}->{$type} -= $cnt;
#      if ($self->{data}->{inv}->{$type} <= 0) {
#         delete $self->{data}->{inv}->{$type};
#      }
#   }
#
#   if ($self->{uis}->{inventory}->{shown}) {
#      $self->{uis}->{inventory}->show; # update if neccesary
#   }
#
#   $self->{uis}->{slots}->show;
#
#   $old_val > 0
#}


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

