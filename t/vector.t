use common::sense;
use Games::Construder::Vector;
use Math::VectorReal;
use Test::More tests => 7;

my $v1 = [1, 2, 3];
my $v2 = [1, -2, -3];

my @res = @{vcross ($v1, $v2)};
my $rest = vector (@$v1) x vector (@$v2);
my @rest = $rest->array;

is ($res[0], $rest[0], "x value ok");
is ($res[1], $rest[1], "y value ok");
is ($res[2], $rest[2], "z value ok");

my ($n, $d) = vplane ([0, 1, 0], [0, 1, 1], [1, 1, 0]);
my ($nt, $dt) = plane (vector (0, 1, 0), vector (0, 1, 1), vector (1, 1, 0));
my @n = @$n;
my @nt = $nt->array;

is ($d, $dt, "plane distance");
is ($n[0], $nt[0], "plane normal x");
is ($n[1], $nt[1], "plane normal y");
is ($n[2], $nt[2], "plane normal z");
