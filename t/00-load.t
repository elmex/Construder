#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'Games::Blockminer' );
}

diag( "Testing Games::Blockminer $Games::Blockminer::VERSION, Perl $], $^X" );
