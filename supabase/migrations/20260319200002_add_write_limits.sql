-- Stage 1: database-enforced write limits.
-- The exception message tokens are consumed by later app-layer error mapping.

create or replace function public.enforce_stage1_write_limits()
returns trigger
language plpgsql
as $$
declare
  table_limit integer;
  limit_token text;
  current_count integer;
begin
  if tg_table_name = 'track_points' then
    table_limit := 50000;
    limit_token := 'UFF_LIMIT_TRACK_POINTS_PER_ACTIVITY';

    if tg_op = 'UPDATE' and new.activity_id is not distinct from old.activity_id then
      return new;
    end if;

    -- Serialize writes per activity so concurrent inserts cannot overrun the cap.
    perform 1
    from public.activities
    where id = new.activity_id
    for update;

    select count(*)
    into current_count
    from public.track_points
    where activity_id = new.activity_id;
  elsif tg_table_name = 'activity_photos' then
    table_limit := 20;
    limit_token := 'UFF_LIMIT_ACTIVITY_PHOTOS_PER_ACTIVITY';

    if tg_op = 'UPDATE' and new.activity_id is not distinct from old.activity_id then
      return new;
    end if;

    perform 1
    from public.activities
    where id = new.activity_id
    for update;

    select count(*)
    into current_count
    from public.activity_photos
    where activity_id = new.activity_id;
  elsif tg_table_name = 'activities' then
    table_limit := 10000;
    limit_token := 'UFF_LIMIT_ACTIVITIES_PER_USER';

    if tg_op = 'UPDATE' and new.user_id is not distinct from old.user_id then
      return new;
    end if;

    perform 1
    from public.profiles
    where id = new.user_id
    for update;

    select count(*)
    into current_count
    from public.activities
    where user_id = new.user_id;
  else
    raise exception 'Unsupported table for enforce_stage1_write_limits: %', tg_table_name;
  end if;

  if current_count >= table_limit then
    raise exception using message = limit_token;
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_track_points_limit on public.track_points;
create trigger enforce_track_points_limit
before insert or update of activity_id on public.track_points
for each row
execute function public.enforce_stage1_write_limits();

drop trigger if exists enforce_activity_photos_limit on public.activity_photos;
create trigger enforce_activity_photos_limit
before insert or update of activity_id on public.activity_photos
for each row
execute function public.enforce_stage1_write_limits();

drop trigger if exists enforce_activities_per_user_limit on public.activities;
create trigger enforce_activities_per_user_limit
before insert or update of user_id on public.activities
for each row
execute function public.enforce_stage1_write_limits();
