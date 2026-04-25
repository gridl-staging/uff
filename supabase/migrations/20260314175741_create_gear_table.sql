create table public.gear (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  gear_type text not null check (gear_type in ('shoe', 'bike', 'component')),
  brand text,
  model text,
  total_distance_meters real not null default 0,
  retired boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
