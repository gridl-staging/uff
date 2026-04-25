-- Stage 1: activity photo metadata boundary
--
-- Adds normalized metadata rows for activity photos. Binary file access remains
-- enforced by storage bucket policies in Stage 5.

create table public.activity_photos (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null,
  thumbnail_path text,
  sort_order int not null check (sort_order >= 0),
  created_at timestamptz not null default now()
);

create index activity_photos_activity_id_idx
  on public.activity_photos (activity_id);

alter table public.activity_photos enable row level security;

create policy "activity_photos_select_own_or_public"
  on public.activity_photos for select
  to authenticated
  using (
    auth.uid() = user_id
    or exists (
      select 1
      from public.activities activity
      where activity.id = activity_id
        and activity.user_id = activity_photos.user_id
        and activity.visibility = 'public'
    )
  );

create policy "activity_photos_insert_own"
  on public.activity_photos for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1
      from public.activities activity
      where activity.id = activity_id
        and activity.user_id = auth.uid()
    )
  );

create policy "activity_photos_delete_own"
  on public.activity_photos for delete
  to authenticated
  using (auth.uid() = user_id);
