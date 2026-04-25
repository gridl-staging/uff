-- Stage 1: owner-column query support indexes for RLS owner predicates.

create index if not exists activities_user_id_idx
  on public.activities (user_id);

create index if not exists gear_user_id_idx
  on public.gear (user_id);

create index if not exists privacy_zones_user_id_idx
  on public.privacy_zones (user_id);
