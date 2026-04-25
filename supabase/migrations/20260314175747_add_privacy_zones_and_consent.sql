-- Stage 7: Privacy zones table and consent fields
--
-- Privacy zones define geographic areas where the owner's track_point coordinates
-- are masked for non-owner viewers. Owner-only RLS — no other user can see, create,
-- or modify another user's privacy zones.
--
-- Consent fields (terms_accepted_at, terms_version) are stored in a separate
-- owner-only table for GDPR baseline. A full consent-history table is deferred
-- beyond this spike.

-- ==========================================================================
-- privacy_zones table
-- ==========================================================================

create table public.privacy_zones (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  label text not null,
  latitude double precision not null,
  longitude double precision not null,
  radius_meters integer not null default 200 check (radius_meters > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ==========================================================================
-- RLS: owner-only access for all operations
-- ==========================================================================

alter table public.privacy_zones enable row level security;

create policy "privacy_zones_select_own"
  on public.privacy_zones for select
  to authenticated
  using (auth.uid() = user_id);

create policy "privacy_zones_insert_own"
  on public.privacy_zones for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "privacy_zones_update_own"
  on public.privacy_zones for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "privacy_zones_delete_own"
  on public.privacy_zones for delete
  to authenticated
  using (auth.uid() = user_id);

-- Consent fields
-- ==========================================================================

create table public.profile_consent (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  terms_accepted_at timestamptz,
  terms_version text
);

alter table public.profile_consent enable row level security;

create policy "profile_consent_select_own"
  on public.profile_consent for select
  to authenticated
  using (auth.uid() = user_id);

create policy "profile_consent_insert_own"
  on public.profile_consent for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "profile_consent_update_own"
  on public.profile_consent for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "profile_consent_delete_own"
  on public.profile_consent for delete
  to authenticated
  using (auth.uid() = user_id);
