-- Wijhati Local Intelligence backend (Supabase / Postgres)
-- Run this once in the Supabase SQL Editor when creating the project.

create table if not exists public.road_reports (
  id text primary key,
  kind text not null,
  latitude double precision not null,
  longitude double precision not null,
  device_id text,
  created_at timestamptz not null default now(),
  confirmed_at timestamptz not null default now()
);

create table if not exists public.local_places (
  id text primary key,
  name text not null,
  category text not null default '',
  note text not null default '',
  latitude double precision not null,
  longitude double precision not null,
  device_id text,
  created_at timestamptz not null default now()
);

alter table public.road_reports enable row level security;
alter table public.local_places enable row level security;

-- Anyone with the anon key can read; anyone can add. No update/delete for anon.
create policy "reports readable" on public.road_reports for select using (true);
create policy "reports insertable" on public.road_reports for insert with check (true);
create policy "places readable" on public.local_places for select using (true);
create policy "places insertable" on public.local_places for insert with check (true);

create table if not exists public.live_locations (
  id text primary key,
  latitude double precision not null,
  longitude double precision not null,
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null
);
alter table public.live_locations enable row level security;
create policy "live readable" on public.live_locations for select using (true);
create policy "live insertable" on public.live_locations for insert with check (true);
create policy "live updatable" on public.live_locations for update using (true) with check (true);
