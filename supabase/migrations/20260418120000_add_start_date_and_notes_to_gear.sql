alter table public.gear
  add column if not exists start_date date;

alter table public.gear
  add column if not exists notes text;
