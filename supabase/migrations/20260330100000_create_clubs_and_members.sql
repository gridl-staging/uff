-- Stage 1 clubs schema and RLS contracts
--
-- Adds clubs, club_members, and club_runs with recursion-safe RLS helper
-- functions and member_count denormalization.

-- ==========================================================================
-- Tables
-- ==========================================================================

-- clubs: the core club entity
-- source: 'user_created' for clubs made in-app, 'auto_discovered' for scraped clubs
-- claimed_by: NULL for unclaimed auto-discovered clubs, set when organizer claims
create table public.clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 100),
  description text check (char_length(description) <= 2000),
  avatar_url text,
  city text,
  state_region text,
  country text default 'US',
  location_lat double precision,
  location_lng double precision,
  -- source tracking for auto-discovery vs user-created
  source text not null default 'user_created' check (source in ('user_created', 'auto_discovered')),
  source_url text,
  source_id text,
  -- creator is the user who made this club in-app (NULL for auto-discovered)
  creator_id uuid references public.profiles(id) on delete set null,
  -- claimed_by is the organizer who verified ownership of an auto-discovered club
  claimed_by uuid references public.profiles(id) on delete set null,
  -- visibility: 'public' (anyone can see/join), 'private' (invite-only, hidden from search)
  visibility text not null default 'public' check (visibility in ('public', 'private')),
  member_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- club_members: who belongs to which club, with what role
-- roles: 'admin' (full control), 'organizer' (manage events/members), 'member' (participate)
-- status: 'active', 'pending' (requested to join private club), 'invited'
create table public.club_members (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'organizer', 'member')),
  status text not null default 'active' check (status in ('active', 'pending', 'invited')),
  joined_at timestamptz not null default now(),
  constraint club_members_club_user_unique unique (club_id, user_id)
);

-- club_runs: scheduled group runs
-- For v1 this is a simple model. Event scheduling/RSVP is future work.
create table public.club_runs (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 200),
  description text check (char_length(description) <= 2000),
  scheduled_at timestamptz not null,
  meeting_point_lat double precision,
  meeting_point_lng double precision,
  meeting_point_name text,
  distance_meters double precision,
  pace_description text,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ==========================================================================
-- Indexes
-- ==========================================================================

create index clubs_city_state on public.clubs (city, state_region)
  where source = 'auto_discovered';
create index clubs_source on public.clubs (source);
create index clubs_creator_id on public.clubs (creator_id)
  where creator_id is not null;
create index club_members_club_id_status on public.club_members (club_id, status);
create index club_members_user_id on public.club_members (user_id);
create index club_runs_club_id_scheduled on public.club_runs (club_id, scheduled_at);

-- ==========================================================================
-- RLS helpers + grants
-- ==========================================================================

-- IMPORTANT: creator_id and claimed_by are passed as parameters (not re-queried
-- from clubs) to avoid infinite RLS recursion.
create or replace function public.can_view_club(
  p_club_id uuid,
  p_visibility text,
  p_creator_id uuid,
  p_claimed_by uuid
)
returns boolean
language sql
security invoker
set search_path = public
stable
as $$
  select (
    p_visibility = 'public'
    or p_creator_id = auth.uid()
    or p_claimed_by = auth.uid()
    or exists (
      select 1
      from public.club_members cm
      where cm.club_id = p_club_id
        and cm.user_id = auth.uid()
        and cm.status = 'active'
    )
  );
$$;

grant execute on function public.can_view_club(uuid, text, uuid, uuid)
  to authenticated, service_role;
revoke execute on function public.can_view_club(uuid, text, uuid, uuid)
  from anon, public;

-- SECURITY DEFINER bypasses RLS on clubs and only returns a visibility boolean.
create or replace function public.is_club_public(p_club_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select visibility = 'public'
  from public.clubs
  where id = p_club_id;
$$;

grant execute on function public.is_club_public(uuid)
  to authenticated, service_role;
revoke execute on function public.is_club_public(uuid)
  from anon, public;

-- Helper: is the current user an active admin/organizer of a given club?
create or replace function public.is_club_admin_or_organizer(p_club_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.club_members
    where club_id = p_club_id
      and user_id = auth.uid()
      and status = 'active'
      and role in ('admin', 'organizer')
  );
$$;

grant execute on function public.is_club_admin_or_organizer(uuid)
  to authenticated, service_role;
revoke execute on function public.is_club_admin_or_organizer(uuid)
  from anon, public;

-- Helper: is the current user an active member (any role) of a given club?
-- SECURITY DEFINER bypasses RLS on club_members to prevent self-referential
-- recursion when called from club_members_select_visible.
create or replace function public.is_active_club_member(p_club_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.club_members
    where club_id = p_club_id
      and user_id = auth.uid()
      and status = 'active'
  );
$$;

grant execute on function public.is_active_club_member(uuid)
  to authenticated, service_role;
revoke execute on function public.is_active_club_member(uuid)
  from anon, public;

-- ==========================================================================
-- Enable RLS
-- ==========================================================================

alter table public.clubs enable row level security;
alter table public.club_members enable row level security;
alter table public.club_runs enable row level security;

-- ==========================================================================
-- Policies
-- ==========================================================================

-- === clubs policies ===

create policy "clubs_select_visible"
  on public.clubs for select
  to authenticated
  using (public.can_view_club(id, visibility, creator_id, claimed_by));

create policy "clubs_insert_creator"
  on public.clubs for insert
  to authenticated
  with check (
    creator_id = auth.uid()
    and source = 'user_created'
  );

create policy "clubs_update_owner"
  on public.clubs for update
  to authenticated
  using (
    creator_id = auth.uid()
    or claimed_by = auth.uid()
    or public.is_club_admin_or_organizer(id)
  );

create policy "clubs_delete_creator_only"
  on public.clubs for delete
  to authenticated
  using (creator_id = auth.uid() and source = 'user_created');

-- === club_members policies ===
-- IMPORTANT: These must NOT call can_view_club or query clubs with RLS.

create policy "club_members_select_visible"
  on public.club_members for select
  to authenticated
  using (
    user_id = auth.uid()
    or (
      status = 'active'
      and (
        public.is_club_public(club_id)
        or public.is_active_club_member(club_id)
      )
    )
    or public.is_club_admin_or_organizer(club_id)
  );

create policy "club_members_insert_self"
  on public.club_members for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and (
      (status = 'active' and role = 'member' and public.is_club_public(club_id))
      or (status = 'pending' and role = 'member' and not public.is_club_public(club_id))
    )
  );

create policy "club_members_insert_admin"
  on public.club_members for insert
  to authenticated
  with check (
    public.is_club_admin_or_organizer(club_id)
    and user_id <> auth.uid()
  );

create policy "club_members_update_admin"
  on public.club_members for update
  to authenticated
  using (public.is_club_admin_or_organizer(club_id));

create policy "club_members_delete_self_or_admin"
  on public.club_members for delete
  to authenticated
  using (
    user_id = auth.uid()
    or public.is_club_admin_or_organizer(club_id)
  );

-- === club_runs policies ===

create policy "club_runs_select_visible"
  on public.club_runs for select
  to authenticated
  using (
    public.is_club_public(club_id)
    or public.is_active_club_member(club_id)
  );

create policy "club_runs_insert_admin_organizer"
  on public.club_runs for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and public.is_club_admin_or_organizer(club_id)
  );

create policy "club_runs_update_creator_or_admin"
  on public.club_runs for update
  to authenticated
  using (
    created_by = auth.uid()
    or public.is_club_admin_or_organizer(club_id)
  );

create policy "club_runs_delete_creator_or_admin"
  on public.club_runs for delete
  to authenticated
  using (
    created_by = auth.uid()
    or public.is_club_admin_or_organizer(club_id)
  );

-- ==========================================================================
-- Denormalization trigger
-- ==========================================================================

create or replace function public.update_club_member_count()
returns trigger
language plpgsql
security definer
as $$
begin
  if TG_OP = 'INSERT' or TG_OP = 'UPDATE' then
    update public.clubs
    set member_count = (
      select count(*)
      from public.club_members
      where club_id = NEW.club_id
        and status = 'active'
    )
    where id = NEW.club_id;
  end if;

  if TG_OP = 'DELETE' or TG_OP = 'UPDATE' then
    update public.clubs
    set member_count = (
      select count(*)
      from public.club_members
      where club_id = OLD.club_id
        and status = 'active'
    )
    where id = OLD.club_id;
  end if;

  return coalesce(NEW, OLD);
end;
$$;

create trigger club_members_count_trigger
  after insert or update or delete on public.club_members
  for each row execute function public.update_club_member_count();
