-- Admin-managed public promotion campaigns. Apply after 03_flutter_feature_parity.sql.
begin;

create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  place_id text not null references public.places(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 160),
  description text not null default '' check (char_length(description) <= 2000),
  discount_label text not null default '' check (char_length(discount_label) <= 100),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint promotions_valid_window check (ends_at > starts_at)
);

alter table public.promotions enable row level security;
revoke all on table public.promotions from public, anon, authenticated;
grant select on table public.promotions to anon, authenticated;
grant insert, update, delete on table public.promotions to authenticated;

drop policy if exists promotions_public_read on public.promotions;
create policy promotions_public_read on public.promotions
  for select to anon, authenticated
  using (
    active
    and starts_at <= statement_timestamp()
    and ends_at > statement_timestamp()
    and exists (
      select 1 from public.places p
      where p.id = promotions.place_id and p.status = 'Verified'
    )
  );

drop policy if exists promotions_admin_read on public.promotions;
create policy promotions_admin_read on public.promotions
  for select to authenticated
  using ((select public.is_admin()));

drop policy if exists promotions_admin_insert on public.promotions;
create policy promotions_admin_insert on public.promotions
  for insert to authenticated
  with check ((select public.is_admin()));

drop policy if exists promotions_admin_update on public.promotions;
create policy promotions_admin_update on public.promotions
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

drop policy if exists promotions_admin_delete on public.promotions;
create policy promotions_admin_delete on public.promotions
  for delete to authenticated
  using ((select public.is_admin()));

create index if not exists promotions_place_schedule_idx
  on public.promotions(place_id, starts_at, ends_at)
  where active;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'promotions'
     ) then
    alter publication supabase_realtime add table public.promotions;
  end if;
end
$$;

create or replace function public.touch_promotion_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end
$$;
revoke all on function public.touch_promotion_updated_at()
  from public, anon, authenticated;

drop trigger if exists promotions_touch_updated_at on public.promotions;
create trigger promotions_touch_updated_at
  before update on public.promotions
  for each row execute function public.touch_promotion_updated_at();

commit;
