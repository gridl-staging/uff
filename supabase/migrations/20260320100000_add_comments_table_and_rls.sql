-- Stage 2 comments contract
--
-- Adds activity comments as a social primitive with centralized visibility checks
-- via public.can_view_activity(...), while keeping delete authorization scoped to
-- the comment author.

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  constraint comments_body_length_check check (char_length(body) between 1 and 500)
);

create index comments_activity_id_created_at_idx
  on public.comments (activity_id, created_at);

alter table public.comments enable row level security;

create policy "comments_select_visible_activity"
  on public.comments for select
  to authenticated
  using (
    exists (
      select 1
      from public.activities activity
      where activity.id = comments.activity_id
        and public.can_view_activity(activity.user_id, activity.visibility)
    )
  );

create policy "comments_insert_visible_activity"
  on public.comments for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1
      from public.activities activity
      where activity.id = comments.activity_id
        and public.can_view_activity(activity.user_id, activity.visibility)
    )
  );

create policy "comments_delete_own"
  on public.comments for delete
  to authenticated
  using (auth.uid() = user_id);
