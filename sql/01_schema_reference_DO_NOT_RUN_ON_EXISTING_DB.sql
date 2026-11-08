-- REFERENCE ONLY: based on READ-ONLY inspection of existing Supabase project pasyalph.
-- Do not execute against existing production: tables already exist and may have policies/triggers.
-- The existing tables are: profiles, places, saved_places, reviews, reports,
-- business_applications, assistant_usage. This is a clean-room schema reference.
create table public.profiles (
 id uuid primary key references auth.users(id),
 role text not null default 'traveler' check(role in ('traveler','owner','admin')),
 settings jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create table public.places (
 id text primary key default gen_random_uuid()::text,
 owner_id uuid references auth.users(id),
 name text not null check(length(name) between 1 and 250),
 category text not null check(category in ('Tourist Spot','Food','Resort','Stay','Shop')),
 image text not null default 'assets/images/taal.jpg',
 description text not null default '', address text not null,
 lat double precision not null check(lat between -90 and 90),
 lng double precision not null check(lng between -180 and 180),
 hours text not null default '', contact text not null default '', rates text not null default '',
 amenities jsonb not null default '[]', routes jsonb not null default '[]',
 status text not null default 'Pending Verification' check(status in ('Verified','Pending Verification','Rejected','Suspended')),
 sponsored boolean not null default false, updated_at timestamptz not null default now()
);
create table public.saved_places (
 user_id uuid not null references auth.users(id), place_id text not null references public.places(id),
 created_at timestamptz not null default now(), primary key(user_id,place_id)
);
create table public.reviews (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 place_id text not null references public.places(id), rating integer not null check(rating between 1 and 5),
 body text not null check(length(trim(body)) between 5 and 2000), created_at timestamptz not null default now()
);
create table public.reports (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 place_id text not null references public.places(id), reason text not null check(length(trim(reason)) between 5 and 1000),
 status text not null default 'Open' check(status in ('Open','Resolved')), created_at timestamptz not null default now()
);
create table public.business_applications (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id),
 legal_name text not null, business_name text not null, address text not null,
 phone text not null, permit_reference text not null, description text not null default '',
 status text not null default 'Pending review' check(status in ('Pending review','Approved','Rejected')),
 created_at timestamptz not null default now()
);
create table public.assistant_usage (
 user_id uuid not null references auth.users(id), day date not null default current_date,
 count integer not null default 1, primary key(user_id,day)
);
-- Every exposed table MUST have RLS enabled before API grants.
