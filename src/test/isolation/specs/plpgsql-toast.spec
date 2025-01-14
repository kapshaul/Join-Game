# Test TOAST behavior in PL/pgSQL procedures with transaction control.
#
# We need to ensure that values stored in PL/pgSQL variables are free
# of external TOAST references, because those could disappear after a
# transaction is committed (leading to errors "missing chunk number
# ... for toast value ...").  The tests here do this by running VACUUM
# in a second session.  Advisory locks are used to have the VACUUM
# kick in at the right time.  The different "assign" steps test
# different code paths for variable assignments in PL/pgSQL.

setup
{
    CREATE TABLE test1 (a int, b text);
    ALTER TABLE test1 ALTER COLUMN b SET STORAGE EXTERNAL;
    INSERT INTO test1 VALUES (1, repeat('foo', 2000));
    CREATE TYPE test2 AS (a bigint, b text);
}

teardown
{
    DROP TABLE test1;
    DROP TYPE test2;
}

session "s1"

setup
{
    SELECT pg_advisory_unlock_all();
}

# assign_simple_var()
step "assign1"
{
do $$
  declare
    x text;
  begin
    select test1.b into x from test1;
    delete from test1;
    commit;
    perform pg_advisory_lock(1);
    raise notice 'x = %', x;
  end;
$$;
}

# assign_simple_var()
step "assign2"
{
do $$
  declare
    x text;
  begin
    x := (select test1.b from test1);
    delete from test1;
    commit;
    perform pg_advisory_lock(1);
    raise notice 'x = %', x;
  end;
$$;
}

# expanded_record_set_field()
step "assign3"
{
do $$
  declare
    r record;
  begin
    select * into r from test1;
    r.b := (select test1.b from test1);
    delete from test1;
    commit;
    perform pg_advisory_lock(1);
    raise notice 'r = %', r;
  end;
$$;
}

# expanded_record_set_fields()
step "assign4"
{
do $$
  declare
    r test2;
  begin
    select * into r from test1;
    delete from test1;
    commit;
    perform pg_advisory_lock(1);
    raise notice 'r = %', r;
  end;
$$;
}

# expanded_record_set_tuple()
step "assign5"
{
do $$
  declare
    r record;
  begin
    for r in select test1.b from test1 loop
      null;
    end loop;
    delete from test1;
    commit;
    perform pg_advisory_lock(1);
    raise notice 'r = %', r;
  end;
$$;
}

session "s2"
setup
{
    SELECT pg_advisory_unlock_all();
}
step "lock"
{
    SELECT pg_advisory_lock(1);
}
step "vacuum"
{
    VACUUM test1;
}
step "unlock"
{
    SELECT pg_advisory_unlock(1);
}

permutation "lock" "assign1" "vacuum" "unlock"
permutation "lock" "assign2" "vacuum" "unlock"
permutation "lock" "assign3" "vacuum" "unlock"
permutation "lock" "assign4" "vacuum" "unlock"
permutation "lock" "assign5" "vacuum" "unlock"
