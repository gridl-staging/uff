\set ON_ERROR_STOP on

-- Stage 2 notification triggers verification.
-- Confirms:
--   1. pg_net extension is installed and callable.
--   2. The shared trigger function public.notify_send_notification() exists.
--   3. Three triggers are registered on the correct tables with correct events.
--   4. The follows trigger only fires on the pending → accepted transition.

-- ---------------------------------------------------------------------------
-- Assertion helper (pg_temp so it auto-drops on disconnect)
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- 1. pg_net extension is installed
-- ---------------------------------------------------------------------------

select pg_temp.assert_true(
  exists (select 1 from pg_extension where extname = 'pg_net'),
  'pg_net extension must be installed'
);

select pg_temp.assert_true(
  exists (select 1 from pg_extension where extname = 'supabase_vault'),
  'supabase_vault extension must be installed'
);

select pg_temp.assert_true(
  to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null,
  'net.http_post(text,jsonb,jsonb,jsonb,integer) must be callable'
);

-- ---------------------------------------------------------------------------
-- 2. Shared trigger function exists
-- ---------------------------------------------------------------------------

select pg_temp.assert_true(
  exists (
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public'
      and p.proname = 'notify_send_notification'
  ),
  'public.notify_send_notification() trigger function must exist'
);

-- Verify it returns trigger (oid 2279)
select pg_temp.assert_true(
  (
    select p.prorettype = 2279
    from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public'
      and p.proname = 'notify_send_notification'
  ),
  'notify_send_notification() must return trigger type'
);

select pg_temp.assert_true(
  (
    select pg_get_functiondef(p.oid) like '%vault.decrypted_secrets%'
    from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public'
      and p.proname = 'notify_send_notification'
  ),
  'notify_send_notification() must read hosted config from vault.decrypted_secrets'
);

-- ---------------------------------------------------------------------------
-- 3. Three triggers registered on correct tables
-- ---------------------------------------------------------------------------

-- Helper: check a trigger exists on a table with the expected event manipulation
create or replace function pg_temp.assert_trigger_exists(
  expected_trigger_name text,
  expected_table text,
  expected_event text,
  expected_timing text
)
returns void
language plpgsql
as $$
declare
  trigger_record record;
begin
  select
    t.trigger_name,
    t.event_manipulation,
    t.action_timing
  into trigger_record
  from information_schema.triggers t
  where t.trigger_schema = 'public'
    and t.event_object_table = expected_table
    and t.trigger_name = expected_trigger_name
    and t.event_manipulation = expected_event;

  if not found then
    raise exception 'Trigger % on public.% (% %) not found',
      expected_trigger_name, expected_table, expected_timing, expected_event;
  end if;

  if trigger_record.action_timing <> expected_timing then
    raise exception 'Trigger % timing: expected %, got %',
      expected_trigger_name, expected_timing, trigger_record.action_timing;
  end if;
end;
$$;

select pg_temp.assert_trigger_exists(
  'notify_kudos_insert', 'kudos', 'INSERT', 'AFTER'
);

select pg_temp.assert_trigger_exists(
  'notify_comments_insert', 'comments', 'INSERT', 'AFTER'
);

select pg_temp.assert_trigger_exists(
  'notify_follows_accepted', 'follows', 'UPDATE', 'AFTER'
);

-- ---------------------------------------------------------------------------
-- 4. Follows trigger has the pending → accepted WHEN clause
-- ---------------------------------------------------------------------------

-- pg_trigger.tgqual stores the internal representation of the WHEN clause.
-- Check that it references both 'pending' and 'accepted' status values.
select pg_temp.assert_true(
  (
    select pg_get_triggerdef(t.oid) like '%pending%'
       and pg_get_triggerdef(t.oid) like '%accepted%'
    from pg_trigger t
    join pg_class c on t.tgrelid = c.oid
    join pg_namespace n on c.relnamespace = n.oid
    where n.nspname = 'public'
      and c.relname = 'follows'
      and t.tgname = 'notify_follows_accepted'
  ),
  'follows trigger WHEN clause must reference pending → accepted transition'
);

-- Verify kudos and comments triggers do NOT have WHEN clauses
-- (they should fire on every INSERT unconditionally)
select pg_temp.assert_true(
  (
    select t.tgqual is null
    from pg_trigger t
    join pg_class c on t.tgrelid = c.oid
    join pg_namespace n on c.relnamespace = n.oid
    where n.nspname = 'public'
      and c.relname = 'kudos'
      and t.tgname = 'notify_kudos_insert'
  ),
  'kudos trigger must fire unconditionally (no WHEN clause)'
);

select pg_temp.assert_true(
  (
    select t.tgqual is null
    from pg_trigger t
    join pg_class c on t.tgrelid = c.oid
    join pg_namespace n on c.relnamespace = n.oid
    where n.nspname = 'public'
      and c.relname = 'comments'
      and t.tgname = 'notify_comments_insert'
  ),
  'comments trigger must fire unconditionally (no WHEN clause)'
);

-- ---------------------------------------------------------------------------
-- 5. All three triggers call the same shared function
-- ---------------------------------------------------------------------------

create or replace function pg_temp.assert_trigger_calls_function(
  trigger_name_param text,
  table_name_param text,
  expected_function text
)
returns void
language plpgsql
as $$
declare
  trigger_def text;
begin
  select pg_get_triggerdef(t.oid)
  into trigger_def
  from pg_trigger t
  join pg_class c on t.tgrelid = c.oid
  join pg_namespace n on c.relnamespace = n.oid
  where n.nspname = 'public'
    and c.relname = table_name_param
    and t.tgname = trigger_name_param;

  if trigger_def is null then
    raise exception 'Trigger % on % not found', trigger_name_param, table_name_param;
  end if;

  if trigger_def not like '%' || expected_function || '%' then
    raise exception 'Trigger % must call %, got: %',
      trigger_name_param, expected_function, trigger_def;
  end if;
end;
$$;

select pg_temp.assert_trigger_calls_function(
  'notify_kudos_insert', 'kudos', 'notify_send_notification'
);

select pg_temp.assert_trigger_calls_function(
  'notify_comments_insert', 'comments', 'notify_send_notification'
);

select pg_temp.assert_trigger_calls_function(
  'notify_follows_accepted', 'follows', 'notify_send_notification'
);

-- All assertions passed
do $$ begin raise notice 'Stage 2 notification triggers verification: ALL PASSED'; end $$;
