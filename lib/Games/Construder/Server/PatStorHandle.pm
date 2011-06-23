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

   $self->init_object_events;

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

sub free_density {
   my ($self) = @_;
   my ($max_dens) = $Games::Construder::Server::RES->get_inventory_max_dens;
   my $mat = $self->{data}->{inv}->{mat};
   my $ent = $self->{data}->{inv}->{ent};
   my $sum;
   for (keys %$mat) {
      my $o = $Games::Construder::Server::RES->get_object_by_type ($_);
      $sum += $o->{density} * $mat->{$_};
   }
   for (keys %$ent) {
      my ($type) = $self->split_invid ($_);
      my $o = $Games::Construder::Server::RES->get_object_by_type ($type);
      $sum += $o->{density} * 1;
   }
   my $free_dens = $max_dens - $sum;
   $free_dens -= $sum;
   $free_dens = 0 if $free_dens < 0;
   ($free_dens, $max_dens)
}

sub space_for {
   my ($self, $type) = @_;

   my ($type, $invid) = $self->split_invid ($type);
   my $fslots  = $self->free_slots;
   my ($fdens) = $self->free_density;
   my $o = $Games::Construder::Server::RES->get_object_by_type ($type);

   my $cnt = not ($o) || $o->{density} <= 0 ? 0 : int ($fdens / $o->{density});
   warn "SPACEFOR $fdens | $cnt: $type, $fslots\n";

   return ($cnt, $fslots < $cnt ? $fslots : $cnt)
}

sub has_space_for {
   my ($self, $type, $cnt) = @_;
   $cnt ||= 1;
   my ($spc, $max) = $self->space_for ($type);
   $spc >= $cnt
}

sub add {
   my ($self, $type, $cnt) = @_;

   my ($type, $invid) = $self->split_invid ($type);
   my ($spc, $max) = $self->space_for ($type);

   my $obj = $Games::Construder::Server::RES->get_object_by_type ($type);
   if ($obj->{permanent}) {
      if (!ref $cnt) {
         unless ($cnt == 1) {
            warn "adding more than 1 permanent entity to a patstore does not work ($type)\n";
            $cnt = 1;
         }
         $cnt = Games::Construder::Server::Objects::instance ($type);
      }

   } elsif (ref $cnt) { # non permanent entity => don't store!
      $cnt = 1;
   }

   if (ref $cnt) { # permanent entity
      return 0 if $spc <= 0;

      my $invid = $type . ":" . $cnt;
      $self->{data}->{inv}->{ent}->{$invid} = $cnt;
      $cnt = 1;

   } else {
      return 0 if $spc <= 0;

      $cnt ||= 1;
      $cnt = $spc if $spc < $cnt;
      warn "ADD $type: $spc | $cnt\n";
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
   sort {
      $Games::Construder::Server::RES->get_object_by_type ($a)->{name}
      cmp
      $Games::Construder::Server::RES->get_object_by_type ($b)->{name}
   } (keys %{$self->{data}->{inv}->{mat}}, keys %{$self->{data}->{inv}->{ent}})
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
   warn "INVCHAN\n";
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

