begin;
set local search_path = util;

create schema if not exists util;

-- if both arguments are equal return the first argument, in all other
-- cases return null
create or replace function single (anyelement, anyelement) returns anyelement
language sql strict immutable parallel safe
as $$ select case when $1 = $2 then $1 else NULL end $$;

-- more complicated version of single used by the single aggregate
create or replace function _single_agg (anyarray, anyelement) returns anyarray
language sql immutable parallel safe
as $$ select case when $1 is null then null
                  when $1 = '{}' then ARRAY[$2]
                  when $1[1] is null and $2 is null then $1
                  when $1[1] = $2 then $1 
                  else null end $$;

create or replace function _raise_not_single (anyelement, anyelement) returns anyarray
language plpgsql immutable parallel safe
as $$ begin
    raise exception 'Single condation violated: %', format('%L != %L', $1, $2);
end $$;

create or replace function _single_err_agg (anyarray, anyelement) returns anyarray
language sql immutable parallel safe
as $$ select case when $1 = '{}' then ARRAY[$2]
                  when $1[1] is null and $2 is null then $1
                  when $1[1] = $2 then $1 
                  else util._raise_not_single($1[1],$2) end $$;

create or replace function _single_final(anyarray) returns anyelement
language sql immutable parallel safe
as $$ select case when $1 is null or $1 = '{}' then null 
                  else $1[1] end $$;

-- If all elements (include nulls) are the same value return the
-- element, otherwise return null.
create aggregate single (anyelement) (
  sfunc = _single_agg,
  finalfunc = _single_final,
  initcond = '{}',
  stype = anyarray,
  parallel = safe
);

-- Like single but raises an error if there is more than one
create aggregate se (anyelement) (
  sfunc = _single_err_agg,
  finalfunc = _single_final,
  initcond = '{}',
  stype = anyarray,
  parallel = safe
);

-- Like single, but ignores nulls
create aggregate intersect_eq (anyelement) (
  sfunc = single, -- note that single is marked stict; thus, null
		  -- values are ignored
  stype = anyelement,
  parallel = safe
);

create or replace function _more_than_one_final(anyarray) returns boolean
language sql immutable
as $$ select case when $1 is null then true 
                  else false end $$;

create aggregate more_than_one (anyelement) (
  sfunc = _single_agg,
  finalfunc = _more_than_one_final,
  initcond = '{}',
  stype = anyarray,
  parallel = safe
);

commit;
