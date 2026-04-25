create table public.activities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  sport_type text not null check (sport_type in ('run', 'ride')),
  started_at timestamptz not null,
  finished_at timestamptz,
  distance_meters real not null,
  duration_seconds integer not null,
  elevation_gain_meters real,
  avg_pace_seconds_per_km real,
  title text,
  description text,
  visibility text not null default 'public' check (visibility in ('public', 'followers', 'private')),
  gear_id uuid references public.gear (id) on delete set null,
  polyline_encoded text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
