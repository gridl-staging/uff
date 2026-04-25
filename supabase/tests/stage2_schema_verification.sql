\set ON_ERROR_STOP on

-- Stage 2 schema verification: structure + behavior + constraints.

create or replace function pg_temp.assert_true(condition boolean, failure_message text)
returns void
language plpgsql
as $$
begin
  if not condition then
    raise exception '%', failure_message;
  end if;
end;
$$;

create or replace function pg_temp.assert_column(
  target_schema text,
  target_table text,
  target_column text,
  expectations jsonb default '{}'::jsonb
)
returns void
language plpgsql
as $$
declare
  column_definition record;
  expected_data_type text := expectations ->> 'data_type';
  expected_udt_name text := expectations ->> 'udt_name';
  expected_nullable text := expectations ->> 'nullable';
  expected_default_expression text := expectations ->> 'default_expression';
  expected_identity_generation text := expectations ->> 'identity_generation';
begin
  select
    data_type,
    udt_name,
    is_nullable,
    column_default,
    identity_generation
  into column_definition
  from information_schema.columns
  where table_schema = target_schema
    and table_name = target_table
    and column_name = target_column;

  if not found then
    raise exception 'Missing column %.%.%', target_schema, target_table, target_column;
  end if;

  if expected_data_type is not null and column_definition.data_type <> expected_data_type then
    raise exception '%.%.% must use data_type %, found %', target_schema, target_table, target_column, expected_data_type, column_definition.data_type;
  end if;

  if expected_udt_name is not null and column_definition.udt_name <> expected_udt_name then
    raise exception '%.%.% must use udt_name %, found %', target_schema, target_table, target_column, expected_udt_name, column_definition.udt_name;
  end if;

  if expected_nullable is not null and column_definition.is_nullable <> expected_nullable then
    raise exception '%.%.% must have nullable flag %, found %', target_schema, target_table, target_column, expected_nullable, column_definition.is_nullable;
  end if;

  if expected_default_expression is not null
    and coalesce(column_definition.column_default, '') <> expected_default_expression then
    raise exception '%.%.% must default to %, found %', target_schema, target_table, target_column, expected_default_expression, coalesce(column_definition.column_default, 'NULL');
  end if;

  if expected_identity_generation is not null
    and coalesce(column_definition.identity_generation, '') <> expected_identity_generation then
    raise exception '%.%.% must use identity generation %, found %', target_schema, target_table, target_column, expected_identity_generation, coalesce(column_definition.identity_generation, 'NULL');
  end if;
end;
$$;

create or replace function pg_temp.assert_fk_constraint(
  source_schema text,
  source_table text,
  source_column text,
  expectations jsonb
)
returns void
language plpgsql
as $$
declare
  referenced_schema text := expectations ->> 'referenced_schema';
  referenced_table text := expectations ->> 'referenced_table';
  expected_delete_action "char" := (expectations ->> 'delete_action')::"char";
  delete_action_name text := case expectations ->> 'delete_action' when 'c' then 'CASCADE' when 'n' then 'SET NULL' else coalesce(expectations ->> 'delete_action', 'UNKNOWN') end;
begin
  perform pg_temp.assert_true(
    exists (
      select 1
      from pg_constraint c
      join pg_class source_rel on source_rel.oid = c.conrelid
      join pg_namespace source_nsp on source_nsp.oid = source_rel.relnamespace
      join pg_class referenced_rel on referenced_rel.oid = c.confrelid
      join pg_namespace referenced_nsp on referenced_nsp.oid = referenced_rel.relnamespace
      join pg_attribute source_att on source_att.attrelid = source_rel.oid and source_att.attnum = any (c.conkey)
      where source_nsp.nspname = source_schema
        and source_rel.relname = source_table
        and source_att.attname = source_column
        and referenced_nsp.nspname = referenced_schema
        and referenced_rel.relname = referenced_table
        and c.contype = 'f'
        and c.confdeltype = expected_delete_action
    ),
    format('%s.%s must reference %s.%s with ON DELETE %s', source_table, source_column, referenced_schema, referenced_table, delete_action_name)
  );
end;
$$;

create or replace function pg_temp.recreate_auth_user(target_user_id uuid, target_email text)
returns void
language plpgsql
as $$
begin
  delete from auth.users
  where id = target_user_id or email = target_email;

  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data
  ) values (
    '00000000-0000-0000-0000-000000000000',
    target_user_id,
    'authenticated',
    'authenticated',
    target_email,
    'not-used-in-tests',
    now(),
    now(),
    now(),
    '{}'::jsonb,
    '{}'::jsonb
  );
end;
$$;

create or replace function pg_temp.recreate_auth_user_with_metadata(
  target_user_id uuid,
  target_email text,
  target_user_metadata jsonb
)
returns void
language plpgsql
as $$
begin
  delete from auth.users
  where id = target_user_id or email = target_email;

  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data
  ) values (
    '00000000-0000-0000-0000-000000000000',
    target_user_id,
    'authenticated',
    'authenticated',
    target_email,
    'not-used-in-tests',
    now(),
    now(),
    now(),
    '{}'::jsonb,
    coalesce(target_user_metadata, '{}'::jsonb)
  );
end;
$$;

-- 1) Required tables must exist.
do $$
declare
  required_tables text[] := array['profiles', 'gear', 'activities', 'track_points', 'splits', 'activity_photos', 'follows', 'kudos', 'comments'];
  table_name text;
begin
  foreach table_name in array required_tables loop
    perform pg_temp.assert_true(
      to_regclass('public.' || table_name) is not null,
      format('Missing required table public.%s', table_name)
    );
  end loop;
end
$$;

-- 2) Column definitions must match the Stage 2 schema.
do $$
begin
  perform pg_temp.assert_column('public', 'profiles', 'id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'profiles', 'display_name', jsonb_build_object('udt_name', 'text', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'profiles', 'avatar_url', jsonb_build_object('udt_name', 'text', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'profiles', 'preferred_units', jsonb_build_object('udt_name', 'text', 'nullable', 'NO', 'default_expression', '''metric''::text'));
  perform pg_temp.assert_column('public', 'profiles', 'default_activity_visibility', jsonb_build_object('udt_name', 'text', 'nullable', 'NO', 'default_expression', '''private''::text'));
  perform pg_temp.assert_column('public', 'profiles', 'created_at', jsonb_build_object('udt_name', 'timestamptz', 'nullable', 'NO', 'default_expression', 'now()'));
  perform pg_temp.assert_column('public', 'profiles', 'updated_at', jsonb_build_object('udt_name', 'timestamptz', 'nullable', 'NO', 'default_expression', 'now()'));

  perform pg_temp.assert_column('public', 'gear', 'id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO', 'default_expression', 'gen_random_uuid()'));
  perform pg_temp.assert_column('public', 'gear', 'user_id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'gear', 'name', jsonb_build_object('udt_name', 'text', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'gear', 'gear_type', jsonb_build_object('udt_name', 'text', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'gear', 'start_date', jsonb_build_object('udt_name', 'date', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'gear', 'brand', jsonb_build_object('udt_name', 'text', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'gear', 'model', jsonb_build_object('udt_name', 'text', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'gear', 'notes', jsonb_build_object('udt_name', 'text', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'gear', 'total_distance_meters', jsonb_build_object('udt_name', 'float4', 'nullable', 'NO', 'default_expression', '0'));
  perform pg_temp.assert_column('public', 'gear', 'retired', jsonb_build_object('udt_name', 'bool', 'nullable', 'NO', 'default_expression', 'false'));
  perform pg_temp.assert_column('public', 'gear', 'created_at', jsonb_build_object('udt_name', 'timestamptz', 'nullable', 'NO', 'default_expression', 'now()'));
  perform pg_temp.assert_column('public', 'gear', 'updated_at', jsonb_build_object('udt_name', 'timestamptz', 'nullable', 'NO', 'default_expression', 'now()'));

  perform pg_temp.assert_column('public', 'activities', 'id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO', 'default_expression', 'gen_random_uuid()'));
  perform pg_temp.assert_column('public', 'activities', 'user_id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'activities', 'sport_type', jsonb_build_object('udt_name', 'text', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'activities', 'started_at', jsonb_build_object('udt_name', 'timestamptz', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'activities', 'finished_at', jsonb_build_object('udt_name', 'timestamptz', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'activities', 'distance_meters', jsonb_build_object('udt_name', 'float4', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'activities', 'duration_seconds', jsonb_build_object('udt_name', 'int4', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'activities', 'elevation_gain_meters', jsonb_build_object('udt_name', 'float4', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'activities', 'avg_pace_seconds_per_km', jsonb_build_object('udt_name', 'float4', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'activities', 'title', jsonb_build_object('udt_name', 'text', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'activities', 'description', jsonb_build_object('udt_name', 'text', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'activities', 'visibility', jsonb_build_object('udt_name', 'text', 'nullable', 'NO', 'default_expression', '''public''::text'));
  perform pg_temp.assert_column('public', 'activities', 'gear_id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'activities', 'polyline_encoded', jsonb_build_object('udt_name', 'text', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'activities', 'created_at', jsonb_build_object('udt_name', 'timestamptz', 'nullable', 'NO', 'default_expression', 'now()'));
  perform pg_temp.assert_column('public', 'activities', 'updated_at', jsonb_build_object('udt_name', 'timestamptz', 'nullable', 'NO', 'default_expression', 'now()'));

  perform pg_temp.assert_column('public', 'track_points', 'id', jsonb_build_object('data_type', 'bigint', 'udt_name', 'int8', 'nullable', 'NO', 'identity_generation', 'ALWAYS'));
  perform pg_temp.assert_column('public', 'track_points', 'activity_id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'track_points', 'timestamp', jsonb_build_object('udt_name', 'timestamptz', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'track_points', 'latitude', jsonb_build_object('udt_name', 'float8', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'track_points', 'longitude', jsonb_build_object('udt_name', 'float8', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'track_points', 'elevation', jsonb_build_object('udt_name', 'float4', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'track_points', 'heart_rate', jsonb_build_object('udt_name', 'int2', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'track_points', 'cadence', jsonb_build_object('udt_name', 'int2', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'track_points', 'power', jsonb_build_object('udt_name', 'int2', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'track_points', 'speed', jsonb_build_object('udt_name', 'float4', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'track_points', 'distance', jsonb_build_object('udt_name', 'float4', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'track_points', 'temperature', jsonb_build_object('udt_name', 'int2', 'nullable', 'YES'));

  perform pg_temp.assert_column('public', 'splits', 'id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO', 'default_expression', 'gen_random_uuid()'));
  perform pg_temp.assert_column('public', 'splits', 'activity_id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'splits', 'split_number', jsonb_build_object('udt_name', 'int4', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'splits', 'distance_meters', jsonb_build_object('udt_name', 'float4', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'splits', 'duration_seconds', jsonb_build_object('udt_name', 'int4', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'splits', 'avg_pace_seconds_per_km', jsonb_build_object('udt_name', 'float4', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'splits', 'avg_heart_rate', jsonb_build_object('udt_name', 'int2', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'splits', 'elevation_change_meters', jsonb_build_object('udt_name', 'float4', 'nullable', 'YES'));

  perform pg_temp.assert_column('public', 'activity_photos', 'id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO', 'default_expression', 'gen_random_uuid()'));
  perform pg_temp.assert_column('public', 'activity_photos', 'activity_id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'activity_photos', 'user_id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'activity_photos', 'storage_path', jsonb_build_object('udt_name', 'text', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'activity_photos', 'thumbnail_path', jsonb_build_object('udt_name', 'text', 'nullable', 'YES'));
  perform pg_temp.assert_column('public', 'activity_photos', 'sort_order', jsonb_build_object('udt_name', 'int4', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'activity_photos', 'created_at', jsonb_build_object('udt_name', 'timestamptz', 'nullable', 'NO', 'default_expression', 'now()'));

  perform pg_temp.assert_column('public', 'follows', 'id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO', 'default_expression', 'gen_random_uuid()'));
  perform pg_temp.assert_column('public', 'follows', 'follower_id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'follows', 'following_id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'follows', 'status', jsonb_build_object('udt_name', 'text', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'follows', 'created_at', jsonb_build_object('udt_name', 'timestamptz', 'nullable', 'NO', 'default_expression', 'now()'));

  perform pg_temp.assert_column('public', 'kudos', 'id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO', 'default_expression', 'gen_random_uuid()'));
  perform pg_temp.assert_column('public', 'kudos', 'activity_id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'kudos', 'user_id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'kudos', 'created_at', jsonb_build_object('udt_name', 'timestamptz', 'nullable', 'NO', 'default_expression', 'now()'));

  perform pg_temp.assert_column('public', 'comments', 'id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO', 'default_expression', 'gen_random_uuid()'));
  perform pg_temp.assert_column('public', 'comments', 'activity_id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'comments', 'user_id', jsonb_build_object('udt_name', 'uuid', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'comments', 'body', jsonb_build_object('udt_name', 'text', 'nullable', 'NO'));
  perform pg_temp.assert_column('public', 'comments', 'created_at', jsonb_build_object('udt_name', 'timestamptz', 'nullable', 'NO', 'default_expression', 'now()'));
end
$$;

-- 3) FKs and indexes must preserve the intended relational behavior.
do $$
begin
  perform pg_temp.assert_fk_constraint('public', 'profiles', 'id', jsonb_build_object('referenced_schema', 'auth', 'referenced_table', 'users', 'delete_action', 'c'));
  perform pg_temp.assert_fk_constraint('public', 'gear', 'user_id', jsonb_build_object('referenced_schema', 'public', 'referenced_table', 'profiles', 'delete_action', 'c'));
  perform pg_temp.assert_fk_constraint('public', 'activities', 'user_id', jsonb_build_object('referenced_schema', 'public', 'referenced_table', 'profiles', 'delete_action', 'c'));
  perform pg_temp.assert_fk_constraint('public', 'activities', 'gear_id', jsonb_build_object('referenced_schema', 'public', 'referenced_table', 'gear', 'delete_action', 'n'));
  perform pg_temp.assert_fk_constraint('public', 'track_points', 'activity_id', jsonb_build_object('referenced_schema', 'public', 'referenced_table', 'activities', 'delete_action', 'c'));
  perform pg_temp.assert_fk_constraint('public', 'splits', 'activity_id', jsonb_build_object('referenced_schema', 'public', 'referenced_table', 'activities', 'delete_action', 'c'));
  perform pg_temp.assert_fk_constraint('public', 'activity_photos', 'activity_id', jsonb_build_object('referenced_schema', 'public', 'referenced_table', 'activities', 'delete_action', 'c'));
  perform pg_temp.assert_fk_constraint('public', 'activity_photos', 'user_id', jsonb_build_object('referenced_schema', 'public', 'referenced_table', 'profiles', 'delete_action', 'c'));
  perform pg_temp.assert_fk_constraint('public', 'follows', 'follower_id', jsonb_build_object('referenced_schema', 'public', 'referenced_table', 'profiles', 'delete_action', 'c'));
  perform pg_temp.assert_fk_constraint('public', 'follows', 'following_id', jsonb_build_object('referenced_schema', 'public', 'referenced_table', 'profiles', 'delete_action', 'c'));
  perform pg_temp.assert_fk_constraint('public', 'kudos', 'activity_id', jsonb_build_object('referenced_schema', 'public', 'referenced_table', 'activities', 'delete_action', 'c'));
  perform pg_temp.assert_fk_constraint('public', 'kudos', 'user_id', jsonb_build_object('referenced_schema', 'public', 'referenced_table', 'profiles', 'delete_action', 'c'));
  perform pg_temp.assert_fk_constraint('public', 'comments', 'activity_id', jsonb_build_object('referenced_schema', 'public', 'referenced_table', 'activities', 'delete_action', 'c'));
  perform pg_temp.assert_fk_constraint('public', 'comments', 'user_id', jsonb_build_object('referenced_schema', 'public', 'referenced_table', 'profiles', 'delete_action', 'c'));

  perform pg_temp.assert_true(
    exists (
      select 1
      from pg_class table_rel
      join pg_namespace table_nsp on table_nsp.oid = table_rel.relnamespace
      join pg_index index_def on index_def.indrelid = table_rel.oid
      join pg_class index_rel on index_rel.oid = index_def.indexrelid
      join lateral (
        select array_agg(att.attname order by key_position.ordinality) as column_names
        from unnest(index_def.indkey) with ordinality as key_position(attnum, ordinality)
        join pg_attribute att on att.attrelid = table_rel.oid and att.attnum = key_position.attnum
      ) index_columns on true
      where table_nsp.nspname = 'public'
        and table_rel.relname = 'track_points'
        and index_rel.relname = 'track_points_activity_id_timestamp_idx'
        and index_columns.column_names = array['activity_id'::name, 'timestamp'::name]
    ),
    'Missing composite index on track_points(activity_id, timestamp)'
  );

  perform pg_temp.assert_true(
    exists (
      select 1
      from pg_class table_rel
      join pg_namespace table_nsp on table_nsp.oid = table_rel.relnamespace
      join pg_index index_def on index_def.indrelid = table_rel.oid
      join pg_class index_rel on index_rel.oid = index_def.indexrelid
      join lateral (
        select array_agg(att.attname order by key_position.ordinality) as column_names
        from unnest(index_def.indkey) with ordinality as key_position(attnum, ordinality)
        join pg_attribute att on att.attrelid = table_rel.oid and att.attnum = key_position.attnum
      ) index_columns on true
      where table_nsp.nspname = 'public'
        and table_rel.relname = 'activity_photos'
        and index_rel.relname = 'activity_photos_activity_id_idx'
        and index_columns.column_names = array['activity_id'::name]
    ),
    'Missing index on activity_photos(activity_id)'
  );

  perform pg_temp.assert_true(
    exists (
      select 1
      from pg_class table_rel
      join pg_namespace table_nsp on table_nsp.oid = table_rel.relnamespace
      join pg_index index_def on index_def.indrelid = table_rel.oid
      join pg_class index_rel on index_rel.oid = index_def.indexrelid
      join lateral (
        select array_agg(att.attname order by key_position.ordinality) as column_names
        from unnest(index_def.indkey) with ordinality as key_position(attnum, ordinality)
        join pg_attribute att on att.attrelid = table_rel.oid and att.attnum = key_position.attnum
      ) index_columns on true
      where table_nsp.nspname = 'public'
        and table_rel.relname = 'follows'
        and index_rel.relname = 'follows_follower_id_status_idx'
        and index_columns.column_names = array['follower_id'::name, 'status'::name]
    ),
    'Missing lookup index on follows(follower_id, status)'
  );

  perform pg_temp.assert_true(
    exists (
      select 1
      from pg_class table_rel
      join pg_namespace table_nsp on table_nsp.oid = table_rel.relnamespace
      join pg_index index_def on index_def.indrelid = table_rel.oid
      join pg_class index_rel on index_rel.oid = index_def.indexrelid
      join lateral (
        select array_agg(att.attname order by key_position.ordinality) as column_names
        from unnest(index_def.indkey) with ordinality as key_position(attnum, ordinality)
        join pg_attribute att on att.attrelid = table_rel.oid and att.attnum = key_position.attnum
      ) index_columns on true
      where table_nsp.nspname = 'public'
        and table_rel.relname = 'follows'
        and index_rel.relname = 'follows_following_id_status_idx'
        and index_columns.column_names = array['following_id'::name, 'status'::name]
    ),
    'Missing lookup index on follows(following_id, status)'
  );

  perform pg_temp.assert_true(
    exists (
      select 1
      from pg_constraint c
      join pg_class rel on rel.oid = c.conrelid
      join pg_namespace nsp on nsp.oid = rel.relnamespace
      where nsp.nspname = 'public'
        and rel.relname = 'kudos'
        and c.conname = 'kudos_activity_id_user_id_key'
        and c.contype = 'u'
    ),
    'Missing unique constraint on kudos(activity_id, user_id)'
  );

  perform pg_temp.assert_true(
    exists (
      select 1
      from pg_class table_rel
      join pg_namespace table_nsp on table_nsp.oid = table_rel.relnamespace
      join pg_index index_def on index_def.indrelid = table_rel.oid
      join pg_class index_rel on index_rel.oid = index_def.indexrelid
      join lateral (
        select array_agg(att.attname order by key_position.ordinality) as column_names
        from unnest(index_def.indkey) with ordinality as key_position(attnum, ordinality)
        join pg_attribute att on att.attrelid = table_rel.oid and att.attnum = key_position.attnum
      ) index_columns on true
      where table_nsp.nspname = 'public'
        and table_rel.relname = 'comments'
        and index_rel.relname = 'comments_activity_id_created_at_idx'
        and index_columns.column_names = array['activity_id'::name, 'created_at'::name]
    ),
    'Missing chronological lookup index on comments(activity_id, created_at)'
  );

  perform pg_temp.assert_true(
    exists (
      select 1
      from pg_constraint c
      join pg_class rel on rel.oid = c.conrelid
      join pg_namespace nsp on nsp.oid = rel.relnamespace
      where nsp.nspname = 'public'
        and rel.relname = 'comments'
        and c.conname = 'comments_body_length_check'
        and c.contype = 'c'
    ),
    'Missing body length check on comments.body'
  );
end
$$;

-- 4) Trigger must provision profiles and auth-user deletes must cascade back out.
do $$
declare
  auth_user_id uuid := '11111111-1111-4111-8111-111111111111';
begin
  perform pg_temp.recreate_auth_user(auth_user_id, 'stage2-trigger-test@example.com');

  perform pg_temp.assert_true(
    exists (
      select 1
      from public.profiles
      where id = auth_user_id
        and preferred_units = 'metric'
        and default_activity_visibility = 'private'
        and created_at is not null
        and updated_at is not null
    ),
    'Profile trigger must create a row with expected defaults and timestamps'
  );

  delete from auth.users where id = auth_user_id;

  perform pg_temp.assert_true(
    not exists (select 1 from public.profiles where id = auth_user_id),
    'Deleting auth.users must cascade delete the matching profile'
  );
end
$$;

-- 5) Smoke test valid inserts plus gear/activity delete behavior.
do $$
declare
  display_name_user_id uuid := '44444444-4444-4444-8444-444444444444';
  full_name_user_id uuid := '55555555-5555-4555-8555-555555555555';
  name_user_id uuid := '66666666-6666-4666-8666-666666666666';
begin
  perform pg_temp.recreate_auth_user_with_metadata(
    display_name_user_id,
    'stage2-display-name-meta@example.com',
    jsonb_build_object(
      'display_name', 'Display Preferred',
      'full_name', 'Should Not Win',
      'name', 'Should Not Win Either',
      'avatar_url', 'https://cdn.example.com/display.png'
    )
  );
  perform pg_temp.assert_true(
    exists (
      select 1
      from public.profiles
      where id = display_name_user_id
        and display_name = 'Display Preferred'
        and avatar_url = 'https://cdn.example.com/display.png'
    ),
    'handle_new_user() must prioritize display_name and persist avatar_url'
  );

  perform pg_temp.recreate_auth_user_with_metadata(
    full_name_user_id,
    'stage2-full-name-meta@example.com',
    jsonb_build_object(
      'full_name', 'Full Name Preferred',
      'avatar_url', 'https://cdn.example.com/full.png'
    )
  );
  perform pg_temp.assert_true(
    exists (
      select 1
      from public.profiles
      where id = full_name_user_id
        and display_name = 'Full Name Preferred'
        and avatar_url = 'https://cdn.example.com/full.png'
    ),
    'handle_new_user() must fall back to full_name when display_name is absent'
  );

  perform pg_temp.recreate_auth_user_with_metadata(
    name_user_id,
    'stage2-name-meta@example.com',
    jsonb_build_object('name', 'Name Fallback')
  );
  perform pg_temp.assert_true(
    exists (
      select 1
      from public.profiles
      where id = name_user_id
        and display_name = 'Name Fallback'
        and avatar_url is null
    ),
    'handle_new_user() must fall back to name and allow null avatar_url'
  );

  delete from auth.users where id in (display_name_user_id, full_name_user_id, name_user_id);
end
$$;

-- 6) Smoke test valid inserts plus gear/activity delete behavior.
do $$
declare
  profile_id uuid := '22222222-2222-4222-8222-222222222222';
  gear_id_value uuid;
  activity_id_value uuid;
  activity_photo_id uuid;
  activity_visibility text;
  activity_gear_id uuid;
begin
  perform pg_temp.recreate_auth_user(profile_id, 'stage2-smoke-test@example.com');

  insert into public.gear (user_id, name, gear_type, brand, model)
  values (profile_id, 'Daily Trainer', 'shoe', 'BrandX', 'ModelY')
  returning id into gear_id_value;

  perform pg_temp.assert_true(
    exists (
      select 1
      from public.gear
      where id = gear_id_value
        and total_distance_meters = 0
        and retired = false
        and created_at is not null
        and updated_at is not null
    ),
    'Gear inserts must apply default distance, retired flag, and timestamps'
  );

  insert into public.activities (
    user_id,
    sport_type,
    started_at,
    finished_at,
    distance_meters,
    duration_seconds,
    gear_id,
    title
  ) values (
    profile_id,
    'run',
    now() - interval '30 minutes',
    now(),
    5000,
    1800,
    gear_id_value,
    'Lunch Run'
  )
  returning id, visibility into activity_id_value, activity_visibility;

  perform pg_temp.assert_true(
    activity_visibility = 'public',
    'activities.visibility must default to public when omitted'
  );

  insert into public.track_points (
    activity_id,
    timestamp,
    latitude,
    longitude,
    elevation,
    heart_rate,
    cadence,
    power,
    speed,
    distance,
    temperature
  )
  values
    (activity_id_value, now() - interval '10 seconds', 40.7128, -74.0060, 10.5, 150, 82, 0, 3.1, 20.0, 18),
    (activity_id_value, now() - interval '5 seconds', 40.7129, -74.0059, 10.7, 152, 83, 0, 3.2, 36.0, 18),
    (activity_id_value, now(), 40.7130, -74.0058, 10.9, 153, 84, 0, 3.3, 52.0, 19);

  insert into public.splits (
    activity_id,
    split_number,
    distance_meters,
    duration_seconds,
    avg_pace_seconds_per_km,
    avg_heart_rate,
    elevation_change_meters
  )
  values (activity_id_value, 1, 1000, 330, 330, 151, 4.0);

  insert into public.activity_photos (
    activity_id,
    user_id,
    storage_path,
    thumbnail_path,
    sort_order
  )
  values (
    activity_id_value,
    profile_id,
    profile_id::text || '/' || activity_id_value::text || '/photo-1.jpg',
    profile_id::text || '/' || activity_id_value::text || '/photo-1-thumb.jpg',
    0
  )
  returning id into activity_photo_id;

  delete from public.gear where id = gear_id_value;

  select gear_id
  into activity_gear_id
  from public.activities
  where id = activity_id_value;

  perform pg_temp.assert_true(
    activity_gear_id is null,
    'Deleting gear must set activities.gear_id to NULL'
  );

  delete from public.activities where id = activity_id_value;

  perform pg_temp.assert_true(
    not exists (select 1 from public.track_points where activity_id = activity_id_value),
    'Deleting activity must cascade delete track_points'
  );

  perform pg_temp.assert_true(
    not exists (select 1 from public.splits where activity_id = activity_id_value),
    'Deleting activity must cascade delete splits'
  );

  perform pg_temp.assert_true(
    not exists (select 1 from public.activity_photos where id = activity_photo_id),
    'Deleting activity must cascade delete activity_photos'
  );

  delete from auth.users where id = profile_id;
end
$$;

-- 7) Invalid values must be rejected by the relevant checks and unique constraints.
do $$
declare
  profile_id uuid := '33333333-3333-4333-8333-333333333333';
  follow_target_id uuid := '77777777-7777-4777-8777-777777777777';
  activity_id_value uuid;
begin
  perform pg_temp.recreate_auth_user(profile_id, 'stage2-constraints-test@example.com');
  perform pg_temp.recreate_auth_user(follow_target_id, 'stage2-follow-target@example.com');

  begin
    update public.profiles
    set preferred_units = 'yards'
    where id = profile_id;
    raise exception 'Expected preferred_units check violation';
  exception when check_violation then
    null;
  end;

  begin
    update public.profiles
    set default_activity_visibility = 'team-only'
    where id = profile_id;
    raise exception 'Expected default_activity_visibility check violation';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.gear (user_id, name, gear_type)
    values (profile_id, 'Bad Gear Type', 'helmet');
    raise exception 'Expected gear_type check violation';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.activities (user_id, sport_type, started_at, distance_meters, duration_seconds)
    values (profile_id, 'swim', now(), 1000, 300);
    raise exception 'Expected sport_type check violation';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.activities (user_id, sport_type, started_at, distance_meters, duration_seconds, visibility)
    values (profile_id, 'run', now(), 1000, 300, 'friends-only');
    raise exception 'Expected visibility check violation';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.follows (follower_id, following_id, status)
    values (profile_id, follow_target_id, 'blocked');
    raise exception 'Expected follows.status check violation';
  exception when check_violation then
    null;
  end;

  begin
    insert into public.follows (follower_id, following_id, status)
    values (profile_id, profile_id, 'pending');
    raise exception 'Expected follows self-follow check violation';
  exception when check_violation then
    null;
  end;

  insert into public.activities (
    user_id,
    sport_type,
    started_at,
    distance_meters,
    duration_seconds
  ) values (
    profile_id,
    'run',
    now(),
    3000,
    1200
  )
  returning id into activity_id_value;

  insert into public.splits (activity_id, split_number, distance_meters, duration_seconds)
  values (activity_id_value, 1, 1000, 400);

  begin
    insert into public.splits (activity_id, split_number, distance_meters, duration_seconds)
    values (activity_id_value, 1, 1000, 410);
    raise exception 'Expected duplicate split unique violation';
  exception when unique_violation then
    null;
  end;

  insert into public.kudos (activity_id, user_id)
  values (activity_id_value, profile_id);

  begin
    insert into public.kudos (activity_id, user_id)
    values (activity_id_value, profile_id);
    raise exception 'Expected duplicate kudos unique violation';
  exception when unique_violation then
    null;
  end;

  insert into public.comments (activity_id, user_id, body) values (activity_id_value, profile_id, 'x');
  insert into public.comments (activity_id, user_id, body) values (activity_id_value, profile_id, repeat('x', 500));

  begin
    insert into public.comments (activity_id, user_id, body) values (activity_id_value, profile_id, ''); raise exception 'Expected comments.body minimum length check violation';
  exception when check_violation then null; end;

  begin
    insert into public.comments (activity_id, user_id, body) values (activity_id_value, profile_id, repeat('x', 501)); raise exception 'Expected comments.body maximum length check violation';
  exception when check_violation then null; end;

  delete from auth.users where id in (profile_id, follow_target_id);
end
$$;

select 'Stage 2 schema verification passed' as result;
