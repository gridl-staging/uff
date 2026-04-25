alter table public.profiles
  add column sport_preferences text[] not null default '{}';
