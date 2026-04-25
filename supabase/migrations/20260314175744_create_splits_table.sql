create table public.splits (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities (id) on delete cascade,
  split_number integer not null,
  distance_meters real not null,
  duration_seconds integer not null,
  avg_pace_seconds_per_km real,
  avg_heart_rate smallint,
  elevation_change_meters real,
  unique (activity_id, split_number)
);
