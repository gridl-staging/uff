create table public.track_points (
  id bigint generated always as identity primary key,
  activity_id uuid not null references public.activities (id) on delete cascade,
  timestamp timestamptz not null,
  latitude double precision not null,
  longitude double precision not null,
  elevation real,
  heart_rate smallint,
  cadence smallint,
  power smallint,
  speed real,
  distance real,
  temperature smallint
);

create index track_points_activity_id_timestamp_idx
  on public.track_points (activity_id, timestamp);
