-- Stage 7: Owner-only track_points access + masked RPC + self-service export
--
-- Replaces the Stage 4 track_points SELECT policy that let any authenticated user
-- read raw GPS coordinates for public activities. Non-owner reads now go through
-- read_activity_track_points(), which masks coordinates falling inside the
-- activity owner's privacy zones.
--
-- Also adds export_my_data() for GDPR self-service data export.

-- ==========================================================================
-- Replace track_points SELECT: non-owner raw access -> owner-only
-- ==========================================================================

drop policy "track_points_select_via_activity" on public.track_points;

create policy "track_points_select_own"
  on public.track_points for select
  to authenticated
  using (
    exists (
      select 1 from public.activities a
      where a.id = activity_id
        and a.user_id = auth.uid()
    )
  );

-- ==========================================================================
-- Masked read RPC for non-owner access to public activity track points
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
        when a.user_id = auth.uid() then false
        when exists (
          select 1 from public.privacy_zones pz
          where pz.user_id = a.user_id
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
    join public.activities a on a.id = tp.activity_id
    where tp.activity_id = p_activity_id
      and (a.user_id = auth.uid() or a.visibility = 'public')
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
-- Self-service data export
-- ==========================================================================

create or replace function public.export_my_data()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  result json;
  caller_id uuid := auth.uid();
begin
  if caller_id is null then
    raise exception 'Not authenticated';
  end if;

  select json_build_object(
    'profile', (
      select row_to_json(p)
      from (
        select
          p.id,
          p.display_name,
          p.avatar_url,
          p.preferred_units,
          p.default_activity_visibility,
          pc.terms_accepted_at,
          pc.terms_version,
          p.created_at,
          p.updated_at
        from profiles p
        left join profile_consent pc on pc.user_id = p.id
        where p.id = caller_id
      ) p
    ),
    'gear', (
      select coalesce(json_agg(row_to_json(g)), '[]'::json)
      from gear g
      where g.user_id = caller_id
    ),
    'activities', (
      select coalesce(json_agg(
        json_build_object(
          'id', a.id,
          'sport_type', a.sport_type,
          'started_at', a.started_at,
          'finished_at', a.finished_at,
          'distance_meters', a.distance_meters,
          'duration_seconds', a.duration_seconds,
          'elevation_gain_meters', a.elevation_gain_meters,
          'avg_pace_seconds_per_km', a.avg_pace_seconds_per_km,
          'title', a.title,
          'description', a.description,
          'visibility', a.visibility,
          'gear_id', a.gear_id,
          'polyline_encoded', a.polyline_encoded,
          'created_at', a.created_at,
          'updated_at', a.updated_at,
          'track_points', (
            select coalesce(
              json_agg(row_to_json(tp) order by tp."timestamp"),
              '[]'::json
            )
            from track_points tp
            where tp.activity_id = a.id
          ),
          'splits', (
            select coalesce(
              json_agg(row_to_json(s) order by s.split_number),
              '[]'::json
            )
            from splits s
            where s.activity_id = a.id
          )
        )
      ), '[]'::json)
      from activities a
      where a.user_id = caller_id
    ),
    'privacy_zones', (
      select coalesce(json_agg(row_to_json(pz)), '[]'::json)
      from privacy_zones pz
      where pz.user_id = caller_id
    ),
    'storage_objects', (
      select coalesce(json_agg(json_build_object(
        'bucket', o.bucket_id,
        'path', o.name
      )), '[]'::json)
      from storage.objects o
      where o.bucket_id in ('avatars', 'activity-photos')
        and o.name like caller_id::text || '/%'
    )
  ) into result;

  return result;
end;
$$;

grant execute on function public.export_my_data() to authenticated;
revoke execute on function public.export_my_data() from anon, public;
