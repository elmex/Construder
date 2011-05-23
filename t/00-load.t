#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'Games::Construder' );
}

diag( "Testing Games::Construder $Games::Construder::VERSION, Perl $], $^X" );
