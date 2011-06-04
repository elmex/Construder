package Games::Construder::Server::Objects;
use common::sense;
use Games::Construder::Server::World;
use Games::Construder;

=head1 NAME

Games::Construder::Server::Objects - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=cut

our $PL;
our $POS;

our %TYPES = (
   36 => \&ia_construction_pad,
);

sub interact {
   my ($player, $type, $pos) = @_;
   $PL  = $player;
   $POS = $pos;

   my $cb = $TYPES{$type}
      or return;

   $cb->();
}

sub ia_construction_pad {
   my $a = Games::Construder::World::get_pattern (@$POS, 0);
   if ($a) {
      my $obj = $Games::Construder::Server::RES->get_object_by_pattern ($a);
      if ($obj) {
         my $score = $Games::Construder::Server::RES->get_type_construct_values ($obj->{type});

         if ($PL->increase_inventory ($obj->{type})) {
            $PL->push_tick_change (score => $score);
            my $a = Games::Construder::World::get_pattern (@$POS, 1);
            my @poses;
            while (@$a) {
               my $pos = [shift @$a, shift @$a, shift @$a];
               push @poses, $pos;
               warn "HL POS @$pos\n";
               $PL->send_client ({
                  cmd   => "highlight",
                  pos   => $pos,
                  color => [0, 0, 1],
                  fade  => -1
               });
            }

            world_mutate_at (\@poses, sub {
               my ($data) = @_;
               $data->[0] = 1;
               1
            }, no_light => 1);

            my $tmr;
            $tmr = AE::timer 1, 0, sub {
               world_mutate_at (\@poses, sub {
                  my ($data) = @_;
                  $data->[0] = 0;
                  1
               });
               undef $tmr;
            };

            $PL->msg ("Added a $obj->{name} to your inventory.");

         } else {
            $PL->msg (1, "The created $obj->{name} would not fit into your inventory!");
         }
      } else {
         $PL->msg (1, "Pattern not recognized!");
      }
   } else {
      $PL->msg (1, "No properly built construction floor found!");
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

