\set ON_ERROR_STOP on

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
  expected_udt_name text := expectations ->> 'udt_name';
  expected_nullable text := expectations ->> 'nullable';
  expected_default_expression text := expectations ->> 'default_expression';
begin
  select
    udt_name,
    is_nullable,
    column_default
  into column_definition
  from information_schema.columns
  where table_schema = target_schema
    and table_name = target_table
    and column_name = target_column;

  if not found then
    raise exception 'Missing column %.%.%', target_schema, target_table, target_column;
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

do $$
begin
  perform pg_temp.assert_column(
    'public',
    'profiles',
    'lthr_bpm',
    jsonb_build_object(
      'udt_name', 'int4',
      'nullable', 'YES'
    )
  );

  perform pg_temp.assert_column(
    'public',
    'profiles',
    'onboarding_completed',
    jsonb_build_object(
      'udt_name', 'bool',
      'nullable', 'NO',
      'default_expression', 'false'
    )
  );

  perform pg_temp.assert_column(
    'public',
    'profiles',
    'default_activity_visibility',
    jsonb_build_object(
      'udt_name', 'text',
      'nullable', 'NO',
      'default_expression', '''private''::text'
    )
  );
end
$$;

do $$
declare
  metadata_user_id uuid := '77777777-7777-4777-8777-777777777777';
begin
  perform pg_temp.recreate_auth_user_with_metadata(
    metadata_user_id,
    'stage3-oauth-metadata@example.com',
    jsonb_build_object(
      'display_name', 'Stage Three User',
      'avatar_url', 'https://cdn.example.com/stage3-avatar.png'
    )
  );

  perform pg_temp.assert_true(
    exists (
      select 1
      from public.profiles
      where id = metadata_user_id
        and display_name = 'Stage Three User'
        and avatar_url = 'https://cdn.example.com/stage3-avatar.png'
        and lthr_bpm is null
        and onboarding_completed = false
        and default_activity_visibility = 'private'
    ),
    'handle_new_user() must still copy OAuth metadata and preserve Stage 3 defaults'
  );

  delete from auth.users where id = metadata_user_id;
end
$$;

select 'Stage 3 schema verification passed' as result;
