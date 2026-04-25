alter table public.profiles
  add column onboarding_completed boolean not null default false;

alter table public.profiles
  alter column default_activity_visibility set default 'private';
