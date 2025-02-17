set enable_seqscan=off;

CREATE TABLE test_macaddr (
	i macaddr
);

INSERT INTO test_macaddr VALUES
	( '22:00:5c:03:55:08' ),
	( '22:00:5c:04:55:08' ),
	( '22:00:5c:05:55:08' ),
	( '22:00:5c:08:55:08' ),
	( '22:00:5c:09:55:08' ),
	( '22:00:5c:10:55:08' )
;

CREATE INDEX idx_macaddr ON test_macaddr USING gin (i);

SELECT * FROM test_macaddr WHERE i<'22:00:5c:08:55:08'::macaddr ORDER BY i;
SELECT * FROM test_macaddr WHERE i<='22:00:5c:08:55:08'::macaddr ORDER BY i;
SELECT * FROM test_macaddr WHERE i='22:00:5c:08:55:08'::macaddr ORDER BY i;
SELECT * FROM test_macaddr WHERE i>='22:00:5c:08:55:08'::macaddr ORDER BY i;
SELECT * FROM test_macaddr WHERE i>'22:00:5c:08:55:08'::macaddr ORDER BY i;
