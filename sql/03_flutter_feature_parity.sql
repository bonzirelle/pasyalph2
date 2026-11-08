-- Additive feature support for the existing PasyalPH project.
begin;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated, service_role;

alter table public.places add column if not exists is_sample boolean not null default false;
alter table public.places add column if not exists sample_reviews jsonb not null default '[]'::jsonb;
alter table public.places add column if not exists source_updated text not null default '';

create or replace function private.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and exists(select 1 from public.profiles where id=(select auth.uid()) and role='admin');
$$;
create or replace function private.is_owner() returns boolean language sql stable security definer set search_path = '' as $$
 select auth.uid() is not null and (private.is_admin() or (exists(select 1 from public.profiles where id=(select auth.uid()) and role='owner') and exists(select 1 from public.business_applications where owner_id=(select auth.uid()) and status='Approved')));
$$;
revoke all on function private.is_admin(), private.is_owner() from public;
grant execute on function private.is_admin(), private.is_owner() to anon, authenticated, service_role;
create or replace function public.is_admin() returns boolean language sql stable security invoker set search_path = '' as $$ select private.is_admin(); $$;
create or replace function public.is_owner() returns boolean language sql stable security invoker set search_path = '' as $$ select private.is_owner(); $$;

alter table public.profiles enable row level security;
alter table public.places enable row level security;
alter table public.saved_places enable row level security;
alter table public.reviews enable row level security;
alter table public.reports enable row level security;
alter table public.business_applications enable row level security;
alter table public.assistant_usage enable row level security;

revoke all on table public.profiles from public, anon, authenticated;
grant select, update(settings) on public.profiles to authenticated;
alter table public.profiles
 add constraint profile_settings_shape check (
  jsonb_typeof(settings)='object' and octet_length(settings::text)<=16384
 ) not valid;
create policy profile_self_scope on public.profiles as restrictive
 for select to authenticated using (id=(select auth.uid()));
create policy profile_self_update_scope on public.profiles as restrictive
 for update to authenticated using (id=(select auth.uid()))
 with check (id=(select auth.uid()));

create policy application_owner_scope on public.business_applications as restrictive
 for select to authenticated
 using (owner_id=(select auth.uid()) or (select private.is_admin()));
create policy application_insert_scope on public.business_applications as restrictive
 for insert to authenticated
 with check (
  (select private.is_admin()) or
  (owner_id=(select auth.uid()) and status='Pending review')
 );
create policy application_admin_update_scope on public.business_applications as restrictive
 for update to authenticated
 using ((select private.is_admin()))
 with check ((select private.is_admin()));
create policy application_admin_update_release on public.business_applications
 for update to authenticated
 using ((select private.is_admin()))
 with check ((select private.is_admin()));
create policy application_admin_delete_scope on public.business_applications as restrictive
 for delete to authenticated using ((select private.is_admin()));

create policy saved_places_owner_scope on public.saved_places as restrictive
 for all to authenticated
 using (user_id=(select auth.uid()))
 with check (user_id=(select auth.uid()));
create policy reviews_owner_insert_scope on public.reviews as restrictive
 for insert to authenticated
 with check (user_id=(select auth.uid()));
create policy reviews_owner_update_scope on public.reviews as restrictive
 for update to authenticated
 using (user_id=(select auth.uid()) or (select private.is_admin()))
 with check (user_id=(select auth.uid()) or (select private.is_admin()));
create policy reviews_owner_delete_scope on public.reviews as restrictive
 for delete to authenticated
 using (user_id=(select auth.uid()) or (select private.is_admin()));
create policy reports_owner_read_scope on public.reports as restrictive
 for select to authenticated
 using (user_id=(select auth.uid()) or (select private.is_admin()));
create policy reports_owner_insert_scope on public.reports as restrictive
 for insert to authenticated
 with check (user_id=(select auth.uid()) and status='Open');
create policy reports_admin_update_scope on public.reports as restrictive
 for update to authenticated
 using ((select private.is_admin()))
 with check ((select private.is_admin()));
create policy reports_admin_update_release on public.reports
 for update to authenticated
 using ((select private.is_admin()))
 with check ((select private.is_admin()));
create policy reports_admin_delete_scope on public.reports as restrictive
 for delete to authenticated using ((select private.is_admin()));
grant update(status) on public.reports to authenticated;
create policy assistant_usage_owner_scope on public.assistant_usage as restrictive
 for select to authenticated using (user_id=(select auth.uid()));

alter function public.handle_new_user() set schema private;
alter function private.handle_new_user() set search_path = '';
revoke execute on function private.handle_new_user() from public, anon, authenticated;

alter function public.moderate_application(uuid,boolean) set schema private;
alter function private.moderate_application(uuid,boolean) set search_path = '';
revoke execute on function private.moderate_application(uuid,boolean) from public, anon;
grant execute on function private.moderate_application(uuid,boolean) to authenticated;
create function public.moderate_application(application_id uuid, approved boolean) returns void language sql security invoker set search_path = '' as $$ select private.moderate_application(application_id,approved); $$;
revoke execute on function public.moderate_application(uuid,boolean) from public, anon;
grant execute on function public.moderate_application(uuid,boolean) to authenticated;

alter function public.consume_assistant_quota() set schema private;
alter function private.consume_assistant_quota() set search_path = '';
revoke execute on function private.consume_assistant_quota() from public, anon;
grant execute on function private.consume_assistant_quota() to authenticated;
create function public.consume_assistant_quota() returns boolean language sql security invoker set search_path = '' as $$ select private.consume_assistant_quota(); $$;
revoke execute on function public.consume_assistant_quota() from public, anon;
grant execute on function public.consume_assistant_quota() to authenticated;
create policy quota_own_read on public.assistant_usage for select to authenticated using (user_id=(select auth.uid()));
grant select on public.assistant_usage to authenticated;

create or replace function public.guard_place_update() returns trigger language plpgsql security invoker set search_path = '' as $$
begin
 if not public.is_admin() and (new.owner_id is distinct from old.owner_id or new.sponsored is distinct from old.sponsored or new.id is distinct from old.id or new.is_sample is distinct from old.is_sample or new.sample_reviews is distinct from old.sample_reviews or new.source_updated is distinct from old.source_updated) then
   raise exception 'Only administrators may change protected listing fields';
 end if;
 new.updated_at=now(); return new;
end $$;
drop trigger if exists places_guard_update on public.places;
create trigger places_guard_update before update on public.places
 for each row execute function public.guard_place_update();

alter table public.business_applications
 add constraint business_application_form_limits check (
  char_length(btrim(legal_name)) between 1 and 250
  and char_length(btrim(business_name)) between 1 and 250
  and char_length(btrim(address)) between 5 and 500
  and char_length(btrim(phone)) between 1 and 30
  and char_length(btrim(permit_reference)) between 1 and 100
  and char_length(btrim(description)) between 20 and 2000
 ) not valid;
alter table public.places
 add constraint places_form_limits check (
  char_length(btrim(name)) between 1 and 250
  and char_length(btrim(address)) between 5 and 500
  and char_length(btrim(description)) between 20 and 2000
  and char_length(hours) <= 250
  and char_length(contact) <= 100
  and char_length(rates) <= 500
 ) not valid;
drop policy places_create on public.places;
create policy places_create on public.places for insert to authenticated with check (
 (select public.is_admin()) or ((select public.is_owner()) and owner_id=(select auth.uid()) and status='Pending Verification' and sponsored=false and is_sample=false and sample_reviews='[]'::jsonb and source_updated='')
);
create policy places_read_scope on public.places as restrictive
 for select to authenticated
 using (status='Verified' or owner_id=(select auth.uid()) or (select private.is_admin()));
create policy places_insert_scope on public.places as restrictive
 for insert to authenticated
 with check (
  (select private.is_admin()) or
  ((select private.is_owner()) and owner_id=(select auth.uid()) and status='Pending Verification')
 );
create policy places_update_scope on public.places as restrictive
 for update to authenticated
 using ((select private.is_admin()) or
  ((select private.is_owner()) and owner_id=(select auth.uid())))
 with check ((select private.is_admin()) or
  ((select private.is_owner()) and owner_id=(select auth.uid()) and status='Pending Verification'));
create policy places_delete_scope on public.places as restrictive
 for delete to authenticated
 using ((select private.is_admin()) or
  ((select private.is_owner()) and owner_id=(select auth.uid()) and status<>'Verified'));

create table public.trip_plans (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 title text not null check(length(title) between 1 and 150),
 place_ids jsonb not null default '[]'::jsonb check(jsonb_typeof(place_ids)='array'),
 notes text not null default '' check(length(notes)<=6000), created_at timestamptz not null default now()
);
alter table public.trip_plans enable row level security;
create policy plans_select on public.trip_plans for select to authenticated using(user_id=(select auth.uid()));
create policy plans_insert on public.trip_plans for insert to authenticated with check(user_id=(select auth.uid()));
create policy plans_update on public.trip_plans for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy plans_delete on public.trip_plans for delete to authenticated using(user_id=(select auth.uid()));
create policy plans_owner_scope on public.trip_plans as restrictive
 for all to authenticated using(user_id=(select auth.uid()))
 with check(user_id=(select auth.uid()));
grant select,insert,update,delete on public.trip_plans to authenticated;
create index trip_plans_user_idx on public.trip_plans(user_id);
create index if not exists places_owner_idx on public.places(owner_id);
create index if not exists applications_owner_idx on public.business_applications(owner_id);
create unique index if not exists applications_active_owner_idx on public.business_applications(owner_id) where status in ('Pending review','Approved');
create index if not exists reports_place_idx on public.reports(place_id);
create index if not exists reviews_user_idx on public.reviews(user_id);
create index if not exists saved_places_place_idx on public.saved_places(place_id);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values ('pasyalph-media','pasyalph-media',true,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy media_read on storage.objects for select to public using(bucket_id='pasyalph-media');
create policy media_insert on storage.objects for insert to authenticated with check(bucket_id='pasyalph-media' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy media_delete on storage.objects for delete to authenticated using(bucket_id='pasyalph-media' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy media_insert_owner_scope on storage.objects as restrictive
 for insert to authenticated
 with check (bucket_id='pasyalph-media' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy media_delete_owner_scope on storage.objects as restrictive
 for delete to authenticated
 using (bucket_id='pasyalph-media' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- Prevent a concurrent approval from making account deletion erase a verified business.
create function private.prevent_verified_owner_deletion() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if exists(select 1 from public.places where owner_id=old.id and status='Verified') then
  raise exception 'Transfer verified business listings before deleting this account';
 end if;
 return old;
end $$;
revoke execute on function private.prevent_verified_owner_deletion() from public,anon,authenticated;
create trigger prevent_verified_owner_deletion before delete on auth.users for each row execute function private.prevent_verified_owner_deletion();

do $$ declare t text; begin
 foreach t in array array['places','reviews','saved_places','profiles','business_applications','reports','trip_plans'] loop
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
    execute format('alter publication supabase_realtime add table public.%I',t);
  end if;
 end loop;
end $$;
commit;
