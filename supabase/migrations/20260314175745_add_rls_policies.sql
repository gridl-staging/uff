-- Stage 4: Row-Level Security policies for Phase 1 tables
--
-- Enables RLS on all five tables and defines ownership/visibility policies.
-- "followers" visibility is treated as "private" until the follower graph exists.
-- No INSERT policy on profiles — handle_new_user() trigger is SECURITY DEFINER.
-- No DELETE policy on profiles — account deletion is a service-role operation (Stage 7).

-- ==========================================================================
-- Enable RLS
-- ==========================================================================

alter table public.profiles enable row level security;
alter table public.gear enable row level security;
alter table public.activities enable row level security;
alter table public.track_points enable row level security;
alter table public.splits enable row level security;

-- ==========================================================================
-- profiles
-- ==========================================================================

create policy "profiles_select_authenticated"
  on public.profiles for select
  to authenticated
  using (true);

create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ==========================================================================
-- gear (fully private — owner only for all operations)
-- ==========================================================================

create policy "gear_select_own"
  on public.gear for select
  to authenticated
  using (auth.uid() = user_id);

create policy "gear_insert_own"
  on public.gear for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "gear_update_own"
  on public.gear for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "gear_delete_own"
  on public.gear for delete
  to authenticated
  using (auth.uid() = user_id);

-- ==========================================================================
-- activities (owner sees all; others see public only)
-- ==========================================================================

create policy "activities_select_own_or_public"
  on public.activities for select
  to authenticated
  using (
    auth.uid() = user_id
    or visibility = 'public'
  );

create policy "activities_insert_own"
  on public.activities for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and (
      gear_id is null
      or exists (
        select 1 from public.gear g
        where g.id = gear_id
          and g.user_id = auth.uid()
      )
    )
  );

create policy "activities_update_own"
  on public.activities for update
  to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (
      gear_id is null
      or exists (
        select 1 from public.gear g
        where g.id = gear_id
          and g.user_id = auth.uid()
      )
    )
  );

create policy "activities_delete_own"
  on public.activities for delete
  to authenticated
  using (auth.uid() = user_id);

-- ==========================================================================
-- track_points (inherits visibility from parent activity)
-- ==========================================================================

create policy "track_points_select_via_activity"
  on public.track_points for select
  to authenticated
  using (
    exists (
      select 1 from public.activities a
      where a.id = activity_id
        and (a.user_id = auth.uid() or a.visibility = 'public')
    )
  );

create policy "track_points_insert_via_activity"
  on public.track_points for insert
  to authenticated
  with check (
    exists (
      select 1 from public.activities a
      where a.id = activity_id
        and a.user_id = auth.uid()
    )
  );

create policy "track_points_delete_via_activity"
  on public.track_points for delete
  to authenticated
  using (
    exists (
      select 1 from public.activities a
      where a.id = activity_id
        and a.user_id = auth.uid()
    )
  );

-- ==========================================================================
-- splits (same pattern as track_points)
-- ==========================================================================

create policy "splits_select_via_activity"
  on public.splits for select
  to authenticated
  using (
    exists (
      select 1 from public.activities a
      where a.id = activity_id
        and (a.user_id = auth.uid() or a.visibility = 'public')
    )
  );

create policy "splits_insert_via_activity"
  on public.splits for insert
  to authenticated
  with check (
    exists (
      select 1 from public.activities a
      where a.id = activity_id
        and a.user_id = auth.uid()
    )
  );

create policy "splits_delete_via_activity"
  on public.splits for delete
  to authenticated
  using (
    exists (
      select 1 from public.activities a
      where a.id = activity_id
        and a.user_id = auth.uid()
    )
  );
