set enable_seqscan=off;

CREATE TABLE test_macaddr8 (
	i macaddr8
);

INSERT INTO test_macaddr8 VALUES
	( '22:00:5c:03:55:08:01:02' ),
	( '22:00:5c:04:55:08:01:02' ),
	( '22:00:5c:05:55:08:01:02' ),
	( '22:00:5c:08:55:08:01:02' ),
	( '22:00:5c:09:55:08:01:02' ),
	( '22:00:5c:10:55:08:01:02' )
;

CREATE INDEX idx_macaddr8 ON test_macaddr8 USING gin (i);

SELECT * FROM test_macaddr8 WHERE i<'22:00:5c:08:55:08:01:02'::macaddr8 ORDER BY i;
SELECT * FROM test_macaddr8 WHERE i<='22:00:5c:08:55:08:01:02'::macaddr8 ORDER BY i;
SELECT * FROM test_macaddr8 WHERE i='22:00:5c:08:55:08:01:02'::macaddr8 ORDER BY i;
SELECT * FROM test_macaddr8 WHERE i>='22:00:5c:08:55:08:01:02'::macaddr8 ORDER BY i;
SELECT * FROM test_macaddr8 WHERE i>'22:00:5c:08:55:08:01:02'::macaddr8 ORDER BY i;
