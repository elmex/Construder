package Games::Construder::Server::World;
use common::sense;
use Games::Construder::Vector;
use Games::Construder;
use Time::HiRes qw/time/;

require Exporter;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   world_init
   world_pos2id
   world_pos2chnkpos
   world_chnkpos2secpos
   world_secpos2chnkpos
   world_pos2relchnkpos
   world_mutate_at
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

our $REGION_SEED = 469392432;
our $REGION_SIZE = 100; # 100x100x100 sections
our $REGION;

sub world_init {
   Games::Construder::World::init ($_[0]);
   Games::Construder::VolDraw::init ();

   region_init ($_[1]);
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

sub world_pos2id {
   my ($pos) = @_;
   join "x", map { $_ < 0 ? "N" . abs ($_) : $_ } @{vfloor ($pos)};
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

sub world_load_at {
   my ($pos) = @_;
   my ($chnk) = world_pos2chnkpos ($pos);
   $Games::Construder::Server::CHNK->check_adjacent_sectors_at_chunk ($chnk);
}

sub world_load_at_chunk {
   my ($chnk) = @_;
   $Games::Construder::Server::CHNK->check_adjacent_sectors_at_chunk ($chnk);
}

sub world_mutate_at {
   my ($poses, $cb, %arg) = @_;

   if (ref $poses->[0]) {
      my $min = [];
      my $max = [];
      for (@$poses) {
         world_load_at ($_); # blocks for now :-/

         $min->[0] = $_->[0] if !defined $min->[0] || $min->[0] > $_->[0];
         $min->[1] = $_->[1] if !defined $min->[1] || $min->[1] > $_->[1];
         $min->[2] = $_->[2] if !defined $min->[2] || $min->[2] > $_->[2];
         $max->[0] = $_->[0] if !defined $max->[0] || $max->[0] < $_->[0];
         $max->[1] = $_->[1] if !defined $max->[1] || $max->[1] < $_->[1];
         $max->[2] = $_->[2] if !defined $max->[2] || $max->[2] < $_->[2];
      }
      warn "MUTL @$min | @$max\n";
      Games::Construder::World::flow_light_query_setup (@$min, @$max);

   } else {
      world_load_at ($poses); # blocks for now :-/

      Games::Construder::World::flow_light_query_setup (@$poses, @$poses);
      $poses = [$poses];
   }

   for my $pos (@$poses) {
      my $b = Games::Construder::World::at (@$pos);
      print "MULT MUTATING (@$b) (AT @$pos)\n";
      if ($cb->($b)) {
         print "MULT MUTATING TO => (@$b) (AT @$pos)\n";
         Games::Construder::World::query_set_at_abs (@$pos, $b);
         unless ($arg{no_light}) {
            my $t1 = time;
            Games::Construder::World::flow_light_at (@{vfloor ($pos)});
            printf "mult light calc took: %f\n", time - $t1;
         }
      }
   }

   Games::Construder::World::query_desetup ();
}

# TODO: - finish multi-mutate
#       - test light!
#       - test construction patterns
#       - pattern multiplizitaet => 1 pattern, mehrere output

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

