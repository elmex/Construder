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

our $REGION_SEED = 42;
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
#  my $unadj_sec = vfloor (vsdiv ($_[0], $CHNKS_P_SEC));
#  my $offs = ($unadj_sec->[1] % 3);
#  my $nchnk = vaddd ($_[0], $offs, 0, $offs);
   vfloor (vsdiv ($_[0], $CHNKS_P_SEC))
}

sub world_secpos2chnkpos {
   my $chnk = vsmul ($_[0], $CHNKS_P_SEC);
#  vsubd ($chnk, $_[0]->[1] % 3, 0, $_[0]->[1] % 3)
   $chnk
}

sub world_pos2relchnkpos {
   my ($pos) = @_;
   my $chnk = world_pos2chnkpos ($pos);
   vsub ($pos, vsmul ($chnk, $CHNK_SIZE))
}


sub world_mutate_at {
   my ($pos, $cb, %arg) = @_;
   my ($chnk) = world_pos2chnkpos ($pos);

   warn "START MUTATE\n";
   Games::Construder::World::query_setup (
      $chnk->[0],
      $chnk->[1],
      $chnk->[2],
      $chnk->[0],
      $chnk->[1],
      $chnk->[2]
   );
   Games::Construder::World::query_load_chunks ();

   my $b = Games::Construder::World::at (@$pos);
   my $was_light = $b->[0] == 40;
   if ($cb->($b)) {
      my $relpos = vfloor (vsubd ($pos,
         $chnk->[0] * $CHNK_SIZE,
         $chnk->[1] * $CHNK_SIZE,
         $chnk->[2] * $CHNK_SIZE));

      Games::Construder::World::query_set_at (@$relpos, $b);
   }

   if ($arg{no_light}) {
      Games::Construder::World::query_desetup ();

   } else {
      Games::Construder::World::query_desetup (1);
      my $t1 = time;
      Games::Construder::World::update_light_at (@{vfloor ($pos)}, $was_light);
      printf "light calc took: %f\n", time - $t1;
      Games::Construder::World::query_desetup ();
   }
   warn "DONE MUTATE\n";
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

