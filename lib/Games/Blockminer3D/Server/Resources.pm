package Games::Blockminer3D::Server::Resources;
use common::sense;
use AnyEvent;
use JSON;
use Digest::MD5 qw/md5_base64/;
use base qw/Object::Event/;

=head1 NAME

Games::Blockminer3D::Server::Resources - desc

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Server::Resources->new (%args)

=cut

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;

   return $self
}

sub _get_file {
   my ($file) = @_;
   open my $f, "<", $file
      or die "Couldn't open '$file': $!\n";
   do { local $/; <$f> }
}

sub load_objects {
   my ($self) = @_;
   my $objects = JSON->new->relaxed->decode (_get_file ("res/objects/types.json"));
   $self->{objects} = $objects;

   for (keys %$objects) {
      my $ob = $objects->{$_};
      if (defined $ob->{texture}) {
         $ob->{texture_id} =
            $self->load_texture ($ob->{texture});
      }
      warn "loaded object $_\n";
   }

   $self->loaded_objects;
}

sub load_texture {
   my ($self, $file) = @_;

   my $tex;
   unless ($tex = $self->{textures}->{$file}) {
      $self->{texture_ids}++;
      $tex = $self->{textures}->{$file} = {
         id => $self->{texture_ids},
      };
   }

   $tex->{data} = _get_file ("res/objects/" . $file);
   $tex->{md5} = md5_base64 ($tex->{data});
   warn "loaded texture $file: $tex->{md5} " . length ($tex->{data}) . "\n";

   $tex->{id}
}

sub loaded_objects : event_cb {
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

