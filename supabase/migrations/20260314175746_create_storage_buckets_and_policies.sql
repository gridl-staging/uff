-- Stage 5: Storage buckets and media policies
--
-- Creates two storage buckets (avatars, activity-photos) with file-size limits,
-- MIME-type restrictions, and path-based storage policies.
--
-- Design decision (activity-photo read access):
--   Option (a) chosen — a storage SELECT policy joins the object path to
--   public.activities and checks visibility, keeping enforcement at the DB layer
--   (consistent with Stage 4 RLS). The path convention
--   {user_id}/{activity_id}/{filename} embeds activity_id in the second folder
--   segment, so the policy matches lower((storage.foldername(name))[2]) against
--   public.activities.id::text and the first path segment against
--   public.activities.user_id::text.
--   "followers" visibility is treated as private until the follower graph exists.
--
-- Path conventions:
--   avatars:         {user_id}/{filename}
--   activity-photos: {user_id}/{activity_id}/{filename}

-- ==========================================================================
-- Create buckets
-- ==========================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('activity-photos', 'activity-photos', false, 10485760, array['image/jpeg', 'image/png', 'image/heic']);

-- ==========================================================================
-- avatars policies (public bucket — anyone can read via public URL)
-- SELECT policy needed even for public buckets: the storage API's internal
-- upsert and delete operations query storage.objects through RLS, so
-- authenticated users need SELECT to manage their own files.
-- ==========================================================================

create policy "avatars_select_authenticated"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'avatars');

create policy "avatars_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "avatars_update_own"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "avatars_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ==========================================================================
-- activity-photos policies (private bucket)
-- Write: restricted to own {user_id}/ path and own activity ids.
-- Read: owner sees own files; others see files whose parent activity is public.
-- ==========================================================================

create policy "activity_photos_select_own_or_public"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'activity-photos'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (
        select 1 from public.activities a
        where a.id::text = lower((storage.foldername(name))[2])
          and a.user_id::text = (storage.foldername(name))[1]
          and a.visibility = 'public'
      )
    )
  );

create policy "activity_photos_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'activity-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1 from public.activities a
      where a.id::text = lower((storage.foldername(name))[2])
        and a.user_id = auth.uid()
    )
  );

create policy "activity_photos_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'activity-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
