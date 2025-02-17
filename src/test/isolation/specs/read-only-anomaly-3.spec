# The example from the paper "A read-only transaction anomaly under snapshot
# isolation"[1].
#
# Here we test that serializable snapshot isolation can avoid the anomaly
# without aborting any tranasctions, by instead causing s3 to be deferred
# until a safe snapshot can be taken.
#
# [1] http://www.cs.umb.edu/~poneil/ROAnom.pdf

setup
{
	CREATE TABLE bank_account (id TEXT PRIMARY KEY, balance DECIMAL NOT NULL);
	INSERT INTO bank_account (id, balance) VALUES ('X', 0), ('Y', 0);
}

teardown
{
	DROP TABLE bank_account;
}

session "s1"
setup 		{ BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE; }
step "s1ry"	{ SELECT balance FROM bank_account WHERE id = 'Y'; }
step "s1wy"	{ UPDATE bank_account SET balance = 20 WHERE id = 'Y'; }
step "s1c" 	{ COMMIT; }

session "s2"
setup		{ BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE; }
step "s2rx"	{ SELECT balance FROM bank_account WHERE id = 'X'; }
step "s2ry"	{ SELECT balance FROM bank_account WHERE id = 'Y'; }
step "s2wx"	{ UPDATE bank_account SET balance = -11 WHERE id = 'X'; }
step "s2c"	{ COMMIT; }

session "s3"
setup		{ BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE READ ONLY DEFERRABLE; }
step "s3r"	{ SELECT id, balance FROM bank_account WHERE id IN ('X', 'Y') ORDER BY id; }
step "s3c"	{ COMMIT; }

permutation "s2rx" "s2ry" "s1ry" "s1wy" "s1c" "s3r" "s2wx" "s2c" "s3c"
