-- Realtime-only change for the existing PasyalPH Supabase project.
-- Adds existing app tables to Supabase Realtime; does not alter data, schema,
-- grants, policies, storage, functions, or authentication configuration.
begin;

do $$
declare
  table_name text;
begin
  if not exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) then
    raise exception 'The supabase_realtime publication does not exist.';
  end if;

  foreach table_name in array array[
    'places',
    'reviews',
    'saved_places',
    'profiles',
    'business_applications',
    'reports',
    'trip_plans'
  ] loop
    if to_regclass(format('%I.%I', 'public', table_name)) is not null
      and not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = table_name
      )
    then
      execute format(
        'alter publication %I add table %I.%I',
        'supabase_realtime',
        'public',
        table_name
      );
    end if;
  end loop;
end
$$;

commit;
