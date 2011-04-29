package Games::Blockminer3D::Client::UI;
use common::sense;
use SDL;
use SDL::TTF;
use OpenGL qw(:all);

use base qw/Object::Event/;

=head1 NAME

Games::Blockminer3D::Client::UI - A simple and small GUI library for the game

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item my $obj = Games::Blockminer3D::Client::UI->new (%args)

=cut

my $BIG_FONT;
my $SMALL_FONT;

sub init_ui {
   unless (SDL::Config->has('SDL_ttf')) {
      Carp::cluck("SDL_ttf support has not been compiled");
   }

   my $font = 'res/FreeMonoBold.ttf';

   unless (SDL::TTF::was_init()) {
      SDL::TTF::init () == 0
         or Carp::cluck "SDL::TTF could not be initialized: "
            . SDL::get_error . "\n";
   }

   $BIG_FONT   = SDL::TTF::open_font ('res/FreeMonoBold.ttf', 50)
      or die "Couldn't load font from res/FreeMonoBold.ttf: " . SDL::get_error . "\n";
   $SMALL_FONT = SDL::TTF::open_font ('res/FreeMonoBold.ttf', 35)
      or die "Couldn't load font from res/FreeMonoBold.ttf: " . SDL::get_error . "\n";
}

sub new {
   my $this  = shift;
   my $class = ref ($this) || $this;
   my $self  = { @_ };
   bless $self, $class;

   $self->init_object_events;

   return $self
}

sub prepare_opengl_texture {
}

sub prepare_sdl_surface {
}

sub update {
   my ($self, $gui_desc) = @_;

   $self->{desc} = $gui_desc if defined $gui_desc;
   $gui_desc = $self->{desc};
   my $win = $gui_desc->{window};
   $self->refresh_window_surface; # creates a new sdl surface for this window

   for my $el (@{$gui_desc->{elements}}) {

      if ($el->{type} eq 'text') {
         $self->place_text ($el->{pos}, $el->{text}, $el->{color});
         # render text

      } elsif ($el->{type} eq 'text_entry') {
         $self->place_text_entry (
            $el->{pos}, $el->{size}, $el->{text}, $el->{edit_key}, $el->{color});
         $self->register_query (
            $el->{edit_key}, $el->{name}, $el->{label} => "line");

      } elsif ($el->{type} eq 'text_field') {
         $self->place_text_entry (
            $el->{pos}, $el->{size},
            $el->{text}, $el->{edit_key},
            $el->{color}, $el->{skipped_lines});

         $self->register_local_shortcut ("down" => sub {
            $el->{skipped_lines}++;
            $self->update;
         });
         $self->register_local_shortcut ("down" => sub {
            $el->{skipped_lines}--;
            $el->{skipped_lines} = 0 if $el->{skipped_lines} < 0;
            $self->update;
         });

         $self->register_query (
            $el->{edit_key}, $el->{name}, $el->{label} => "text");

      } elsif ($el->{type} eq 'gauge') {
         $self->place_gauge (
            $el->{pos}, $el->{size}, $el->{label}, $el->{fill}, $el->{color}
         );

      } elsif ($el->{type} eq 'model') {
         $self->place_model (
            $el->{pos}, $el->{size}, $el->{number}, $el->{label}
         );
      }
   }

   $self->render_view; # refresh rendering to opengl texture
}

sub render_view {
   my ($self) = @_;

   ($self->{gl_id}, $self->{gl_model_descs})
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

