# Games::Construder - A 3D Game written in Perl with an infinite and modifiable world.
# Copyright (C) 2011  Robin Redeker
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
package Games::Construder::Logging;
use common::sense;
require Exporter;
use POSIX qw/floor/;
use Time::HiRes qw/time/;
our @ISA = qw/Exporter/;
our @EXPORT = qw/
   ctr_log
   ctr_cond_log
   ctr_enable_log_categories
   ctr_disable_log_categories
/;

=head1 NAME

Games::Construder::Logging - This module takes care of logging construder client and server output.

=over 4

=cut

# well known:
#    debug
#    error
#    warn
#    info
#    profile
our %CATEGORIES;
our $LOGFILE;
our $LOGFILE_FH;

sub ctr_enable_log_categories {
   my (@cats) = @_;

   if (grep { $_ eq 'all' } @cats) {
      (%CATEGORIES) = (all => 1);
   } else {
      $CATEGORIES{$_} = 1 for @cats;
   }
}
sub ctr_disable_log_categories {
   my (@cats) = @_;

   if (grep { $_ eq 'all' } @cats) {
      (%CATEGORIES) = (error => 1);
   } else {
      delete $CATEGORIES{$_} for @cats;
   }
}

sub ctr_cond_log {
   my ($category, $cb, $elsecb) = @_;

   if ($CATEGORIES{$category} || $CATEGORIES{all}) {
      $cb->(1)
   } else {
      $elsecb->(0) if $elsecb;
   }
}

sub ctr_log {
   my ($category, $fmt, @args) = @_;
   return unless $CATEGORIES{$category} || $CATEGORIES{all};

   my $t = time;
   my $ti = int $t;
   my $tr = $t - $ti;

   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime ($ti);

   my $date =
      sprintf "%04d-%02d-%02d %02d:%02d:%02d",
         $year + 1900, $mon + 1, $mday, $hour, $min, $sec;
   my $str = sprintf "%s+%5.4f [%s]: $fmt", $date, $tr, $category, @args;
   $str .= "\n" unless $str =~ /\n$/s;

   if ($LOGFILE ne '') {
      unless ($LOGFILE_FH) {
         open my $fh, ">>", $LOGFILE;
         $LOGFILE_FH = $fh;
      }
      print $LOGFILE_FH $str;
   }

   print $str;
}

=back

=head1 AUTHOR

Robin Redeker, C<< <elmex@ta-sa.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2011 Robin Redeker, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License.

=cut

1;

