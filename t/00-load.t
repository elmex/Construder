#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'Games::Blockminer3D' );
}

diag( "Testing Games::Blockminer3D $Games::Blockminer3D::VERSION, Perl $], $^X" );
