/* contrib/cube/cube--1.1--1.2.sql */

-- complain if script is sourced in psql, rather than via ALTER EXTENSION
\echo Use "ALTER EXTENSION cube UPDATE TO '1.2'" to load this file. \quit

-- Update procedure signatures the hard way.
-- We use to_regprocedure() so that query doesn't fail if run against 9.6beta1 definitions,
-- wherein the signatures have been updated already.  In that case to_regprocedure() will
-- return NULL and no updates will happen.

UPDATE pg_catalog.pg_proc SET
  proargtypes = pg_catalog.array_to_string(newtypes::pg_catalog.oid[], ' ')::pg_catalog.oidvector,
  pronargs = pg_catalog.array_length(newtypes, 1)
FROM (VALUES
(NULL::pg_catalog.text, NULL::pg_catalog.regtype[]), -- establish column types
('g_cube_consistent(internal,cube,int4,oid,internal)', '{internal,cube,int2,oid,internal}'),
('g_cube_distance(internal,cube,smallint,oid)', '{internal,cube,smallint,oid,internal}')
) AS update_data (oldproc, newtypes)
WHERE oid = pg_catalog.to_regprocedure(oldproc);

ALTER FUNCTION cube_in(cstring) PARALLEL SAFE;
ALTER FUNCTION cube(float8[], float8[]) PARALLEL SAFE;
ALTER FUNCTION cube(float8[]) PARALLEL SAFE;
ALTER FUNCTION cube_out(cube) PARALLEL SAFE;
ALTER FUNCTION cube_eq(cube, cube) PARALLEL SAFE;
ALTER FUNCTION cube_ne(cube, cube) PARALLEL SAFE;
ALTER FUNCTION cube_lt(cube, cube) PARALLEL SAFE;
ALTER FUNCTION cube_gt(cube, cube) PARALLEL SAFE;
ALTER FUNCTION cube_le(cube, cube) PARALLEL SAFE;
ALTER FUNCTION cube_ge(cube, cube) PARALLEL SAFE;
ALTER FUNCTION cube_cmp(cube, cube) PARALLEL SAFE;
ALTER FUNCTION cube_contains(cube, cube) PARALLEL SAFE;
ALTER FUNCTION cube_contained(cube, cube) PARALLEL SAFE;
ALTER FUNCTION cube_overlap(cube, cube) PARALLEL SAFE;
ALTER FUNCTION cube_union(cube, cube) PARALLEL SAFE;
ALTER FUNCTION cube_inter(cube, cube) PARALLEL SAFE;
ALTER FUNCTION cube_size(cube) PARALLEL SAFE;
ALTER FUNCTION cube_subset(cube, int4[]) PARALLEL SAFE;
ALTER FUNCTION cube_distance(cube, cube) PARALLEL SAFE;
ALTER FUNCTION distance_chebyshev(cube, cube) PARALLEL SAFE;
ALTER FUNCTION distance_taxicab(cube, cube) PARALLEL SAFE;
ALTER FUNCTION cube_dim(cube) PARALLEL SAFE;
ALTER FUNCTION cube_ll_coord(cube, int4) PARALLEL SAFE;
ALTER FUNCTION cube_ur_coord(cube, int4) PARALLEL SAFE;
ALTER FUNCTION cube_coord(cube, int4) PARALLEL SAFE;
ALTER FUNCTION cube_coord_llur(cube, int4) PARALLEL SAFE;
ALTER FUNCTION cube(float8) PARALLEL SAFE;
ALTER FUNCTION cube(float8, float8) PARALLEL SAFE;
ALTER FUNCTION cube(cube, float8) PARALLEL SAFE;
ALTER FUNCTION cube(cube, float8, float8) PARALLEL SAFE;
ALTER FUNCTION cube_is_point(cube) PARALLEL SAFE;
ALTER FUNCTION cube_enlarge(cube, float8, int4) PARALLEL SAFE;
ALTER FUNCTION g_cube_consistent(internal, cube, smallint, oid, internal) PARALLEL SAFE;
ALTER FUNCTION g_cube_compress(internal) PARALLEL SAFE;
ALTER FUNCTION g_cube_decompress(internal) PARALLEL SAFE;
ALTER FUNCTION g_cube_penalty(internal, internal, internal) PARALLEL SAFE;
ALTER FUNCTION g_cube_picksplit(internal, internal) PARALLEL SAFE;
ALTER FUNCTION g_cube_union(internal, internal) PARALLEL SAFE;
ALTER FUNCTION g_cube_same(cube, cube, internal) PARALLEL SAFE;
ALTER FUNCTION g_cube_distance(internal, cube, smallint, oid, internal) PARALLEL SAFE;
