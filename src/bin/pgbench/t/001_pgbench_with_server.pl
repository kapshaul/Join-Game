use strict;
use warnings;

use PostgresNode;
use TestLib;
use Test::More;

# start a pgbench specific server
my $node = get_new_node('main');
$node->init;
$node->start;

# invoke pgbench, with parameters:
#   $opts: options as a string to be split on spaces
#   $stat: expected exit status
#   $out: reference to a regexp list that must match stdout
#   $err: reference to a regexp list that must match stderr
#   $name: name of test for error messages
#   $files: reference to filename/contents dictionnary
#   @args: further raw options or arguments
sub pgbench
{
	my ($opts, $stat, $out, $err, $name, $files, @args) = @_;
	my @cmd = ('pgbench', split /\s+/, $opts);
	my @filenames = ();
	if (defined $files)
	{

		# note: files are ordered for determinism
		for my $fn (sort keys %$files)
		{
			my $filename = $node->basedir . '/' . $fn;
			push @cmd, '-f', $filename;

			# cleanup file weight
			$filename =~ s/\@\d+$//;

			#push @filenames, $filename;
			# filenames are expected to be unique on a test
			if (-e $filename)
			{
				ok(0, "$filename must not already exists");
				unlink $filename or die "cannot unlink $filename: $!";
			}
			append_to_file($filename, $$files{$fn});
		}
	}

	push @cmd, @args;

	$node->command_checks_all(\@cmd, $stat, $out, $err, $name);

	# cleanup?
	#unlink @filenames or die "cannot unlink files (@filenames): $!";

	return;
}

# Test concurrent insertion into table with UNIQUE oid column.  DDL expects
# GetNewOidWithIndex() to successfully avoid violating uniqueness for indexes
# like pg_class_oid_index and pg_proc_oid_index.  This indirectly exercises
# LWLock and spinlock concurrency.  This test makes a 5-MiB table.

$node->safe_psql('postgres',
	    'CREATE UNLOGGED TABLE oid_tbl () WITH OIDS; '
	  . 'ALTER TABLE oid_tbl ADD UNIQUE (oid);');

pgbench(
	'--no-vacuum --client=5 --protocol=prepared --transactions=25',
	0,
	[qr{processed: 125/125}],
	[qr{^$}],
	'concurrency OID generation',
	{
		'001_pgbench_concurrent_oid_generation' =>
		  'INSERT INTO oid_tbl SELECT FROM generate_series(1,1000);'
	});

# cleanup
$node->safe_psql('postgres', 'DROP TABLE oid_tbl;');

# Trigger various connection errors
pgbench(
	'no-such-database',
	1,
	[qr{^$}],
	[
		qr{connection to database "no-such-database" failed},
		qr{FATAL:  database "no-such-database" does not exist}
	],
	'no such database');

pgbench(
	'-S -t 1', 1, [qr{^$}],
	[qr{Perhaps you need to do initialization}],
	'run without init');

# Initialize pgbench tables scale 1
pgbench(
	'-i', 0,
	[qr{^$}],
	[
		qr{creating tables},       qr{vacuuming},
		qr{creating primary keys}, qr{done\.}
	],
	'pgbench scale 1 initialization',);

# Again, with all possible options
pgbench(
	'--initialize --init-steps=dtpvg --scale=1 --unlogged-tables --fillfactor=98 --foreign-keys --quiet --tablespace=pg_default --index-tablespace=pg_default',
	0,
	[qr{^$}i],
	[
		qr{dropping old tables},
		qr{creating tables},
		qr{vacuuming},
		qr{creating primary keys},
		qr{creating foreign keys},
		qr{done\.}
	],
	'pgbench scale 1 initialization');

# Test interaction of --init-steps with legacy step-selection options
pgbench(
	'--initialize --init-steps=dtpvgvv --no-vacuum --foreign-keys --unlogged-tables',
	0,
	[qr{^$}],
	[
		qr{dropping old tables},
		qr{creating tables},
		qr{creating primary keys},
		qr{.* of .* tuples \(.*\) done},
		qr{creating foreign keys},
		qr{done\.}
	],
	'pgbench --init-steps');

# Run all builtin scripts, for a few transactions each
pgbench(
	'--transactions=5 -Dfoo=bla --client=2 --protocol=simple --builtin=t'
	  . ' --connect -n -v -n',
	0,
	[
		qr{builtin: TPC-B},
		qr{clients: 2\b},
		qr{processed: 10/10},
		qr{mode: simple}
	],
	[qr{^$}],
	'pgbench tpcb-like');

pgbench(
	'--transactions=20 --client=5 -M extended --builtin=si -C --no-vacuum -s 1',
	0,
	[
		qr{builtin: simple update},
		qr{clients: 5\b},
		qr{threads: 1\b},
		qr{processed: 100/100},
		qr{mode: extended}
	],
	[qr{scale option ignored}],
	'pgbench simple update');

pgbench(
	'-t 100 -c 7 -M prepared -b se --debug',
	0,
	[
		qr{builtin: select only},
		qr{clients: 7\b},
		qr{threads: 1\b},
		qr{processed: 700/700},
		qr{mode: prepared}
	],
	[
		qr{vacuum},    qr{client 0}, qr{client 1}, qr{sending},
		qr{receiving}, qr{executing}
	],
	'pgbench select only');

# check if threads are supported
my $nthreads = 2;

{
	my ($stderr);
	run_log([ 'pgbench', '-j', '2', '--bad-option' ], '2>', \$stderr);
	$nthreads = 1 if $stderr =~ m/threads are not supported on this platform/;
}

# run custom scripts
pgbench(
	"-t 100 -c 1 -j $nthreads -M prepared -n",
	0,
	[
		qr{type: multiple scripts},
		qr{mode: prepared},
		qr{script 1: .*/001_pgbench_custom_script_1},
		qr{weight: 2},
		qr{script 2: .*/001_pgbench_custom_script_2},
		qr{weight: 1},
		qr{processed: 100/100}
	],
	[qr{^$}],
	'pgbench custom scripts',
	{
		'001_pgbench_custom_script_1@1' => q{-- select only
\set aid random(1, :scale * 100000)
SELECT abalance::INTEGER AS balance
  FROM pgbench_accounts
  WHERE aid=:aid;
},
		'001_pgbench_custom_script_2@2' => q{-- special variables
BEGIN;
\set foo 1
-- cast are needed for typing under -M prepared
SELECT :foo::INT + :scale::INT * :client_id::INT AS bla;
COMMIT;
}
	});

pgbench(
	'-n -t 10 -c 1 -M simple',
	0,
	[
		qr{type: .*/001_pgbench_custom_script_3},
		qr{processed: 10/10},
		qr{mode: simple}
	],
	[qr{^$}],
	'pgbench custom script',
	{
		'001_pgbench_custom_script_3' => q{-- select only variant
\set aid random(1, :scale * 100000)
BEGIN;
SELECT abalance::INTEGER AS balance
  FROM pgbench_accounts
  WHERE aid=:aid;
COMMIT;
}
	});

pgbench(
	'-n -t 10 -c 2 -M extended',
	0,
	[
		qr{type: .*/001_pgbench_custom_script_4},
		qr{processed: 20/20},
		qr{mode: extended}
	],
	[qr{^$}],
	'pgbench custom script',
	{
		'001_pgbench_custom_script_4' => q{-- select only variant
\set aid random(1, :scale * 100000)
BEGIN;
SELECT abalance::INTEGER AS balance
  FROM pgbench_accounts
  WHERE aid=:aid;
COMMIT;
}
	});

# test expressions
# command 1..3 and 23 depend on random seed which is used to call srandom.
pgbench(
	'--random-seed=5432 -t 1 -Dfoo=-10.1 -Dbla=false -Di=+3 -Dminint=-9223372036854775808 -Dn=null -Dt=t -Df=of -Dd=1.0',
	0,
	[ qr{type: .*/001_pgbench_expressions}, qr{processed: 1/1} ],
	[
		qr{setting random seed to 5432\b},

		# After explicit seeding, the four random checks (1-3,20) are
		# deterministic
		qr{command=1.: int 18\b},      # uniform random
		qr{command=2.: int 101\b},     # exponential random
		qr{command=3.: int 1415\b},    # gaussian random
		qr{command=4.: int 4\b},
		qr{command=5.: int 5\b},
		qr{command=6.: int 6\b},
		qr{command=7.: int 7\b},
		qr{command=8.: int 8\b},
		qr{command=9.: int 9\b},
		qr{command=10.: int 10\b},
		qr{command=11.: int 11\b},
		qr{command=12.: int 12\b},
		qr{command=15.: double 15\b},
		qr{command=16.: double 16\b},
		qr{command=17.: double 17\b},
		qr{command=18.: int 9223372036854775807\b},
		qr{command=20.: int 2\b},    # zipfian random
		qr{command=21.: double -27\b},
		qr{command=22.: double 1024\b},
		qr{command=23.: double 1\b},
		qr{command=24.: double 1\b},
		qr{command=25.: double -0.125\b},
		qr{command=26.: double -0.125\b},
		qr{command=27.: double -0.00032\b},
		qr{command=28.: double 8.50705917302346e\+0?37\b},
		qr{command=29.: double 1e\+0?30\b},
		qr{command=30.: boolean false\b},
		qr{command=31.: boolean true\b},
		qr{command=32.: int 32\b},
		qr{command=33.: int 33\b},
		qr{command=34.: double 34\b},
		qr{command=35.: int 35\b},
		qr{command=36.: int 36\b},
		qr{command=37.: double 37\b},
		qr{command=38.: int 38\b},
		qr{command=39.: int 39\b},
		qr{command=40.: boolean true\b},
		qr{command=41.: null\b},
		qr{command=42.: null\b},
		qr{command=43.: boolean true\b},
		qr{command=44.: boolean true\b},
		qr{command=45.: boolean true\b},
		qr{command=46.: int 46\b},
		qr{command=47.: boolean true\b},
		qr{command=48.: boolean true\b},
		qr{command=49.: int -5817877081768721676\b},
		qr{command=50.: boolean true\b},
		qr{command=51.: int -7793829335365542153\b},
		qr{command=52.: int -?\d+\b},
		qr{command=53.: boolean true\b},
		qr{command=65.: int 65\b},
		qr{command=74.: int 74\b},
		qr{command=83.: int 83\b},
		qr{command=86.: int 86\b},
		qr{command=93.: int 93\b},
		qr{command=95.: int 0\b},
		qr{command=96.: int 1\b},       # :scale
		qr{command=97.: int 0\b},       # :client_id
		qr{command=98.: int 5432\b},    # :random_seed
	],
	'pgbench expressions',
	{
		'001_pgbench_expressions' => q{-- integer functions
\set i1 debug(random(10, 19))
\set i2 debug(random_exponential(100, 199, 10.0))
\set i3 debug(random_gaussian(1000, 1999, 10.0))
\set i4 debug(abs(-4))
\set i5 debug(greatest(5, 4, 3, 2))
\set i6 debug(11 + least(-5, -4, -3, -2))
\set i7 debug(int(7.3))
-- integer arithmetic and bit-wise operators
\set i8 debug(17 / (4|1) + ( 4 + (7 >> 2)))
\set i9 debug(- (3 * 4 - (-(~ 1) + -(~ 0))) / -1 + 3 % -1)
\set ia debug(10 + (0 + 0 * 0 - 0 / 1))
\set ib debug(:ia + :scale)
\set ic debug(64 % (((2 + 1 * 2 + (1 # 2) | 4 * (2 & 11)) - (1 << 2)) + 2))
-- double functions and operators
\set d1 debug(sqrt(+1.5 * 2.0) * abs(-0.8E1))
\set d2 debug(double(1 + 1) * (-75.0 / :foo))
\set pi debug(pi() * 4.9)
\set d4 debug(greatest(4, 2, -1.17) * 4.0 * Ln(Exp(1.0)))
\set d5 debug(least(-5.18, .0E0, 1.0/0) * -3.3)
-- forced overflow
\set maxint debug(:minint - 1)
-- reset a variable
\set i1 0
-- yet another integer function
\set id debug(random_zipfian(1, 9, 1.3))
--- pow and power
\set poweri debug(pow(-3,3))
\set powerd debug(pow(2.0,10))
\set poweriz debug(pow(0,0))
\set powerdz debug(pow(0.0,0.0))
\set powernegi debug(pow(-2,-3))
\set powernegd debug(pow(-2.0,-3.0))
\set powernegd2 debug(power(-5.0,-5.0))
\set powerov debug(pow(9223372036854775807, 2))
\set powerov2 debug(pow(10,30))
-- comparisons and logical operations
\set c0 debug(1.0 = 0.0 and 1.0 != 0.0)
\set c1 debug(0 = 1 Or 1.0 = 1)
\set c4 debug(case when 0 < 1 then 32 else 0 end)
\set c5 debug(case when true then 33 else 0 end)
\set c6 debug(case when false THEN -1 when 1 = 1 then 13 + 19 + 2.0 end )
\set c7 debug(case when (1 > 0) and (1 >= 0) and (0 < 1) and (0 <= 1) and (0 != 1) and (0 = 0) and (0 <> 1) then 35 else 0 end)
\set c8 debug(CASE \
                WHEN (1.0 > 0.0) AND (1.0 >= 0.0) AND (0.0 < 1.0) AND (0.0 <= 1.0) AND \
                     (0.0 != 1.0) AND (0.0 = 0.0) AND (0.0 <> 1.0) AND (0.0 = 0.0) \
                  THEN 36 \
                  ELSE 0 \
              END)
\set c9 debug(CASE WHEN NOT FALSE THEN 3 * 12.3333334 END)
\set ca debug(case when false then 0 when 1-1 <> 0 then 1 else 38 end)
\set cb debug(10 + mod(13 * 7 + 12, 13) - mod(-19 * 11 - 17, 19))
\set cc debug(NOT (0 > 1) AND (1 <= 1) AND NOT (0 >= 1) AND (0 < 1) AND \
    NOT (false and true) AND (false OR TRUE) AND (NOT :f) AND (NOT FALSE) AND \
    NOT (NOT TRUE))
-- NULL value and associated operators
\set n0 debug(NULL + NULL * exp(NULL))
\set n1 debug(:n0)
\set n2 debug(NOT (:n0 IS NOT NULL OR :d1 IS NULL))
\set n3 debug(:n0 IS NULL AND :d1 IS NOT NULL AND :d1 NOTNULL)
\set n4 debug(:n0 ISNULL AND NOT :n0 IS TRUE AND :n0 IS NOT FALSE)
\set n5 debug(CASE WHEN :n IS NULL THEN 46 ELSE NULL END)
-- use a variables of all types
\set n6 debug(:n IS NULL AND NOT :f AND :t)
-- conditional truth
\set cs debug(CASE WHEN 1 THEN TRUE END AND CASE WHEN 1.0 THEN TRUE END AND CASE WHEN :n THEN NULL ELSE TRUE END)
-- hash functions
\set h0 debug(hash(10, 5432))
\set h1 debug(:h0 = hash_murmur2(10, 5432))
\set h3 debug(hash_fnv1a(10, 5432))
\set h4 debug(hash(10))
\set h5 debug(hash(10) = hash(10, :default_seed))
-- lazy evaluation
\set zy 0
\set yz debug(case when :zy = 0 then -1 else (1 / :zy) end)
\set yz debug(case when :zy = 0 or (1 / :zy) < 0 then -1 else (1 / :zy) end)
\set yz debug(case when :zy > 0 and (1 / :zy) < 0 then (1 / :zy) else 1 end)
-- substitute variables of all possible types
\set v0 NULL
\set v1 TRUE
\set v2 5432
\set v3 -54.21E-2
SELECT :v0, :v1, :v2, :v3;
-- if tests
\set nope 0
\if 1 > 0
\set id debug(65)
\elif 0
\set nope 1
\else
\set nope 1
\endif
\if 1 < 0
\set nope 1
\elif 1 > 0
\set ie debug(74)
\else
\set nope 1
\endif
\if 1 < 0
\set nope 1
\elif 1 < 0
\set nope 1
\else
\set if debug(83)
\endif
\if 1 = 1
\set ig debug(86)
\elif 0
\set nope 1
\endif
\if 1 = 0
\set nope 1
\elif 1 <> 0
\set ih debug(93)
\endif
-- must be zero if false branches where skipped
\set nope debug(:nope)
-- check automatic variables
\set sc debug(:scale)
\set ci debug(:client_id)
\set rs debug(:random_seed)
}
	});

# random determinism when seeded
$node->safe_psql('postgres',
	'CREATE UNLOGGED TABLE seeded_random(seed INT8 NOT NULL, rand TEXT NOT NULL, val INTEGER NOT NULL);'
);

# same value to check for determinism
my $seed = int(rand(1000000000));
for my $i (1, 2)
{
	pgbench(
		"--random-seed=$seed -t 1",
		0,
		[qr{processed: 1/1}],
		[qr{setting random seed to $seed\b}],
		"random seeded with $seed",
		{
			"001_pgbench_random_seed_$i" => q{-- test random functions
\set ur random(1000, 1999)
\set er random_exponential(2000, 2999, 2.0)
\set gr random_gaussian(3000, 3999, 3.0)
\set zr random_zipfian(4000, 4999, 1.5)
INSERT INTO seeded_random(seed, rand, val) VALUES
  (:random_seed, 'uniform', :ur),
  (:random_seed, 'exponential', :er),
  (:random_seed, 'gaussian', :gr),
  (:random_seed, 'zipfian', :zr);
}
		});
}

# check that all runs generated the same 4 values
my ($ret, $out, $err) = $node->psql('postgres',
	'SELECT seed, rand, val, COUNT(*) FROM seeded_random GROUP BY seed, rand, val'
);

ok($ret == 0,  "psql seeded_random count ok");
ok($err eq '', "psql seeded_random count stderr is empty");
ok($out =~ /\b$seed\|uniform\|1\d\d\d\|2/,
	"psql seeded_random count uniform");
ok( $out =~ /\b$seed\|exponential\|2\d\d\d\|2/,
	"psql seeded_random count exponential");
ok( $out =~ /\b$seed\|gaussian\|3\d\d\d\|2/,
	"psql seeded_random count gaussian");
ok($out =~ /\b$seed\|zipfian\|4\d\d\d\|2/,
	"psql seeded_random count zipfian");

$node->safe_psql('postgres', 'DROP TABLE seeded_random;');

# backslash commands
pgbench(
	'-t 1', 0,
	[
		qr{type: .*/001_pgbench_backslash_commands},
		qr{processed: 1/1},
		qr{shell-echo-output}
	],
	[qr{command=8.: int 1\b}],
	'pgbench backslash commands',
	{
		'001_pgbench_backslash_commands' => q{-- run set
\set zero 0
\set one 1.0
-- sleep
\sleep :one ms
\sleep 100 us
\sleep 0 s
\sleep :zero
-- setshell and continuation
\setshell another_one\
  echo \
    :one
\set n debug(:another_one)
-- shell
\shell echo shell-echo-output
}
	});

# trigger many expression errors
my @errors = (

	# [ test name, expected status, expected stderr, script ]
	# SQL
	[
		'sql syntax error',
		0,
		[
			qr{ERROR:  syntax error},
			qr{prepared statement .* does not exist}
		],
		q{-- SQL syntax error
    SELECT 1 + ;
}
	],
	[
		'sql too many args', 1, [qr{statement has too many arguments.*\b9\b}],
		q{-- MAX_ARGS=10 for prepared
\set i 0
SELECT LEAST(:i, :i, :i, :i, :i, :i, :i, :i, :i, :i, :i);
}
	],

	# SHELL
	[
		'shell bad command',                    0,
		[qr{\(shell\) .* meta-command failed}], q{\shell no-such-command}
	],
	[
		'shell undefined variable', 0,
		[qr{undefined variable ":nosuchvariable"}],
		q{-- undefined variable in shell
\shell echo ::foo :nosuchvariable
}
	],
	[ 'shell missing command', 1, [qr{missing command }], q{\shell} ],
	[
		'shell too many args', 1, [qr{too many arguments in command "shell"}],
		q{-- 257 arguments to \shell
\shell echo \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F \
 0 1 2 3 4 5 6 7 8 9 A B C D E F
}
	],

	# SET
	[
		'set syntax error',                  1,
		[qr{syntax error in command "set"}], q{\set i 1 +}
	],
	[
		'set no such function',         1,
		[qr{unexpected function name}], q{\set i noSuchFunction()}
	],
	[
		'set invalid variable name', 0,
		[qr{invalid variable name}], q{\set . 1}
	],
	[
		'set int overflow',                   0,
		[qr{double to int overflow for 100}], q{\set i int(1E32)}
	],
	[ 'set division by zero', 0, [qr{division by zero}], q{\set i 1/0} ],
	[
		'set bigint out of range', 0,
		[qr{bigint out of range}], q{\set i 9223372036854775808 / -1}
	],
	[
		'set undefined variable',
		0,
		[qr{undefined variable "nosuchvariable"}],
		q{\set i :nosuchvariable}
	],
	[ 'set unexpected char', 1, [qr{unexpected character .;.}], q{\set i ;} ],
	[
		'set too many args',
		0,
		[qr{too many function arguments}],
		q{\set i least(0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16)}
	],
	[
		'set empty random range',          0,
		[qr{empty range given to random}], q{\set i random(5,3)}
	],
	[
		'set random range too large',
		0,
		[qr{random range is too large}],
		q{\set i random(-9223372036854775808, 9223372036854775807)}
	],
	[
		'set gaussian param too small',
		0,
		[qr{gaussian param.* at least 2}],
		q{\set i random_gaussian(0, 10, 1.0)}
	],
	[
		'set exponential param greater 0',
		0,
		[qr{exponential parameter must be greater }],
		q{\set i random_exponential(0, 10, 0.0)}
	],
	[
		'set zipfian param to 1',
		0,
		[qr{zipfian parameter must be in range \(0, 1\) U \(1, \d+\]}],
		q{\set i random_zipfian(0, 10, 1)}
	],
	[
		'set zipfian param too large',
		0,
		[qr{zipfian parameter must be in range \(0, 1\) U \(1, \d+\]}],
		q{\set i random_zipfian(0, 10, 1000000)}
	],
	[
		'set non numeric value',                     0,
		[qr{malformed variable "foo" value: "bla"}], q{\set i :foo + 1}
	],
	[ 'set no expression',    1, [qr{syntax error}],      q{\set i} ],
	[ 'set missing argument', 1, [qr{missing argument}i], q{\set} ],
	[
		'set not a bool',                      0,
		[qr{cannot coerce double to boolean}], q{\set b NOT 0.0}
	],
	[
		'set not an int',                   0,
		[qr{cannot coerce boolean to int}], q{\set i TRUE + 2}
	],
	[
		'set not a double',                    0,
		[qr{cannot coerce boolean to double}], q{\set d ln(TRUE)}
	],
	[
		'set case error',
		1,
		[qr{syntax error in command "set"}],
		q{\set i CASE TRUE THEN 1 ELSE 0 END}
	],
	[
		'set random error',                 0,
		[qr{cannot coerce boolean to int}], q{\set b random(FALSE, TRUE)}
	],
	[
		'set number of args mismatch',        1,
		[qr{unexpected number of arguments}], q{\set d ln(1.0, 2.0))}
	],
	[
		'set at least one arg',               1,
		[qr{at least one argument expected}], q{\set i greatest())}
	],

	# SETSHELL
	[
		'setshell not an int',                0,
		[qr{command must return an integer}], q{\setshell i echo -n one}
	],
	[ 'setshell missing arg', 1, [qr{missing argument }], q{\setshell var} ],
	[
		'setshell no such command',   0,
		[qr{could not read result }], q{\setshell var no-such-command}
	],

	# SLEEP
	[
		'sleep undefined variable',      0,
		[qr{sleep: undefined variable}], q{\sleep :nosuchvariable}
	],
	[
		'sleep too many args',    1,
		[qr{too many arguments}], q{\sleep too many args}
	],
	[
		'sleep missing arg', 1,
		[ qr{missing argument}, qr{\\sleep} ], q{\sleep}
	],
	[
		'sleep unknown unit',         1,
		[qr{unrecognized time unit}], q{\sleep 1 week}
	],

	# MISC
	[
		'misc invalid backslash command',         1,
		[qr{invalid command .* "nosuchcommand"}], q{\nosuchcommand}
	],
	[ 'misc empty script', 1, [qr{empty command list for script}], q{} ],
	[
		'bad boolean',                     0,
		[qr{malformed variable.*trueXXX}], q{\set b :badtrue or true}
	],);


for my $e (@errors)
{
	my ($name, $status, $re, $script) = @$e;
	my $n = '001_pgbench_error_' . $name;
	$n =~ s/ /_/g;
	pgbench(
		'-n -t 1 -Dfoo=bla -Dnull=null -Dtrue=true -Done=1 -Dzero=0.0 -Dbadtrue=trueXXX -M prepared',
		$status,
		[ $status ? qr{^$} : qr{processed: 0/1} ],
		$re,
		'pgbench script error: ' . $name,
		{ $n => $script });
}

# zipfian cache array overflow
pgbench(
	'-t 1', 0,
	[ qr{processed: 1/1}, qr{zipfian cache array overflowed 1 time\(s\)} ],
	[qr{^}],
	'pgbench zipfian array overflow on random_zipfian',
	{
		'001_pgbench_random_zipfian' => q{
\set i random_zipfian(1, 100, 0.5)
\set i random_zipfian(2, 100, 0.5)
\set i random_zipfian(3, 100, 0.5)
\set i random_zipfian(4, 100, 0.5)
\set i random_zipfian(5, 100, 0.5)
\set i random_zipfian(6, 100, 0.5)
\set i random_zipfian(7, 100, 0.5)
\set i random_zipfian(8, 100, 0.5)
\set i random_zipfian(9, 100, 0.5)
\set i random_zipfian(10, 100, 0.5)
\set i random_zipfian(11, 100, 0.5)
\set i random_zipfian(12, 100, 0.5)
\set i random_zipfian(13, 100, 0.5)
\set i random_zipfian(14, 100, 0.5)
\set i random_zipfian(15, 100, 0.5)
\set i random_zipfian(16, 100, 0.5)
}
	});

# throttling
pgbench(
	'-t 100 -S --rate=100000 --latency-limit=1000000 -c 2 -n -r',
	0,
	[ qr{processed: 200/200}, qr{builtin: select only} ],
	[qr{^$}],
	'pgbench throttling');

pgbench(

	# given the expected rate and the 2 ms tx duration, at most one is executed
	'-t 10 --rate=100000 --latency-limit=1 -n -r',
	0,
	[
		qr{processed: [01]/10},
		qr{type: .*/001_pgbench_sleep},
		qr{above the 1.0 ms latency limit: [01]/}
	],
	[qr{^$}],
	'pgbench late throttling',
	{ '001_pgbench_sleep' => q{\sleep 2ms} });

# return a list of files from directory $dir matching regexpr $re
# this works around glob portability and escaping issues
sub list_files
{
	my ($dir, $re) = @_;
	opendir my $dh, $dir or die "cannot opendir $dir: $!";
	my @files = grep /$re/, readdir $dh;
	closedir $dh or die "cannot closedir $dir: $!";
	return map { $dir . '/' . $_ } @files;
}

# check log contents and cleanup
sub check_pgbench_logs
{
	my ($dir, $prefix, $nb, $min, $max, $re) = @_;

	# $prefix is simple enough, thus does not need escaping
	my @logs = list_files($dir, qr{^$prefix\..*$});
	ok(@logs == $nb, "number of log files");
	ok(grep(/\/$prefix\.\d+(\.\d+)?$/, @logs) == $nb, "file name format");

	my $log_number = 0;
	for my $log (sort @logs)
	{
		eval {
			open my $fh, '<', $log or die "$@";
			my @contents = <$fh>;
			my $clen     = @contents;
			ok( $min <= $clen && $clen <= $max,
				"transaction count for $log ($clen)");
			ok( grep($re, @contents) == $clen,
				"transaction format for $prefix");
			close $fh or die "$@";
		};
	}
	ok(unlink(@logs), "remove log files");
	return;
}

my $bdir = $node->basedir;

# with sampling rate
pgbench(
	"-n -S -t 50 -c 2 --log --sampling-rate=0.5",
	0,
	[ qr{select only}, qr{processed: 100/100} ],
	[ qr{^$} ],
	'pgbench logs',
	undef,
	"--log-prefix=$bdir/001_pgbench_log_2");

check_pgbench_logs($bdir, '001_pgbench_log_2', 1, 8, 92,
	qr{^0 \d{1,2} \d+ \d \d+ \d+$});

# check log file in some detail
pgbench(
	"-n -b se -t 10 -l",
	0, [ qr{select only}, qr{processed: 10/10} ], [ qr{^$} ],
	'pgbench logs contents', undef,
	"--log-prefix=$bdir/001_pgbench_log_3");

check_pgbench_logs($bdir, '001_pgbench_log_3', 1, 10, 10,
	qr{^\d \d{1,2} \d+ \d \d+ \d+$});

# done
$node->stop;
done_testing();
