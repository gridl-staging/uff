-- Stage 1 social contracts + centralized visibility
--
-- Adds follows and kudos tables with RLS, then centralizes read authorization
-- for followers visibility across activities, splits, photo metadata, storage,
-- and masked track-point RPC reads.

-- ==========================================================================
-- Social tables
-- ==========================================================================

create table public.follows (
  id uuid primary key default gen_random_uuid(),
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  constraint follows_follower_following_key unique (follower_id, following_id),
  constraint follows_no_self_follow check (follower_id <> following_id)
);

create index follows_follower_id_status_idx
  on public.follows (follower_id, status);

create index follows_following_id_status_idx
  on public.follows (following_id, status);

create table public.kudos (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint kudos_activity_id_user_id_key unique (activity_id, user_id)
);

create index kudos_activity_id_idx
  on public.kudos (activity_id);

-- ==========================================================================
-- Centralized activity visibility helper
-- ==========================================================================

create or replace function public.can_view_activity(
  p_activity_owner_id uuid,
  p_activity_visibility text
)
returns boolean
language sql
security invoker
set search_path = public
stable
as $$
  select (
    auth.uid() = p_activity_owner_id
    or p_activity_visibility = 'public'
    or (
      p_activity_visibility = 'followers'
      and exists (
        select 1
        from public.follows follow_edge
        where follow_edge.follower_id = auth.uid()
          and follow_edge.following_id = p_activity_owner_id
          and follow_edge.status = 'accepted'
      )
    )
  );
$$;

grant execute on function public.can_view_activity(uuid, text)
  to authenticated, service_role;
revoke execute on function public.can_view_activity(uuid, text)
  from anon, public;

-- ==========================================================================
-- Rebuild follower-aware read policies from one helper
-- ==========================================================================

drop policy if exists "activities_select_own_or_public" on public.activities;
create policy "activities_select_own_or_public"
  on public.activities for select
  to authenticated
  using (public.can_view_activity(user_id, visibility));

drop policy if exists "splits_select_via_activity" on public.splits;
create policy "splits_select_via_activity"
  on public.splits for select
  to authenticated
  using (
    exists (
      select 1
      from public.activities activity
      where activity.id = splits.activity_id
        and public.can_view_activity(activity.user_id, activity.visibility)
    )
  );

drop policy if exists "activity_photos_select_own_or_public" on public.activity_photos;
create policy "activity_photos_select_own_or_public"
  on public.activity_photos for select
  to authenticated
  using (
    exists (
      select 1
      from public.activities activity
      where activity.id = activity_photos.activity_id
        and public.can_view_activity(activity.user_id, activity.visibility)
    )
  );

drop policy if exists "activity_photos_select_own_or_public" on storage.objects;
create policy "activity_photos_select_own_or_public"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'activity-photos'
    and exists (
      select 1
      from public.activities activity
      where activity.id::text = lower((storage.foldername(name))[2])
        and activity.user_id::text = (storage.foldername(name))[1]
        and public.can_view_activity(activity.user_id, activity.visibility)
    )
  );

-- ==========================================================================
-- Keep raw track_points owner-only; extend masked RPC through helper
-- ==========================================================================

create or replace function public.read_activity_track_points(p_activity_id uuid)
returns table (
  id bigint,
  activity_id uuid,
  "timestamp" timestamptz,
  latitude double precision,
  longitude double precision,
  elevation real,
  heart_rate smallint,
  cadence smallint,
  power smallint,
  speed real,
  distance real,
  temperature smallint
)
language sql
security definer
set search_path = public
stable
as $$
  with zone_masked as (
    select
      tp.id,
      tp.activity_id,
      tp."timestamp",
      tp.latitude as raw_lat,
      tp.longitude as raw_lon,
      tp.elevation,
      tp.heart_rate,
      tp.cadence,
      tp.power,
      tp.speed,
      tp.distance,
      tp.temperature,
      case
        when activity.user_id = auth.uid() then false
        when exists (
          select 1 from public.privacy_zones pz
          where pz.user_id = activity.user_id
            and sqrt(
              power((tp.latitude - pz.latitude) * 111320, 2) +
              power(
                (tp.longitude - pz.longitude) * 111320
                  * cos(radians(pz.latitude)),
                2
              )
            ) <= pz.radius_meters
        ) then true
        else false
      end as is_masked
    from public.track_points tp
    join public.activities activity on activity.id = tp.activity_id
    where tp.activity_id = p_activity_id
      and public.can_view_activity(activity.user_id, activity.visibility)
  )
  select
    zm.id,
    zm.activity_id,
    zm."timestamp",
    case when zm.is_masked then null else zm.raw_lat end,
    case when zm.is_masked then null else zm.raw_lon end,
    zm.elevation,
    zm.heart_rate,
    zm.cadence,
    zm.power,
    zm.speed,
    zm.distance,
    zm.temperature
  from zone_masked zm
  order by zm."timestamp";
$$;

grant execute on function public.read_activity_track_points(uuid) to authenticated;
revoke execute on function public.read_activity_track_points(uuid) from anon, public;

-- ==========================================================================
-- RLS for follows and kudos
-- ==========================================================================

alter table public.follows enable row level security;
alter table public.kudos enable row level security;

create policy "follows_select_participants"
  on public.follows for select
  to authenticated
  using (auth.uid() = follower_id or auth.uid() = following_id);

create policy "follows_insert_requester"
  on public.follows for insert
  to authenticated
  with check (
    auth.uid() = follower_id
    and status = 'pending'
    and follower_id <> following_id
  );

create policy "follows_update_following_accept"
  on public.follows for update
  to authenticated
  using (
    auth.uid() = following_id
    and status = 'pending'
  )
  with check (
    auth.uid() = following_id
    and status = 'accepted'
    and follower_id <> following_id
  );

create policy "follows_delete_participants"
  on public.follows for delete
  to authenticated
  using (auth.uid() = follower_id or auth.uid() = following_id);

create policy "kudos_select_visible_activity"
  on public.kudos for select
  to authenticated
  using (
    exists (
      select 1
      from public.activities activity
      where activity.id = kudos.activity_id
        and public.can_view_activity(activity.user_id, activity.visibility)
    )
  );

create policy "kudos_insert_visible_activity"
  on public.kudos for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1
      from public.activities activity
      where activity.id = kudos.activity_id
        and public.can_view_activity(activity.user_id, activity.visibility)
    )
  );

create policy "kudos_delete_own"
  on public.kudos for delete
  to authenticated
  using (auth.uid() = user_id);
