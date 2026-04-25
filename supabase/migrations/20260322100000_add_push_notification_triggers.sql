-- Push notification triggers for kudos, comments, and follows.
--
-- One shared PL/pgSQL trigger function constructs the WebhookPayload shape
-- that send-notification/index.ts expects (type, table, schema, record,
-- old_record) and dispatches via pg_net (async, non-blocking).
--
-- URL and webhook secret are read from database settings when available.
-- The local stack falls back to host.docker.internal for the API URL, while
-- hosted environments should still set the database-level values explicitly:
--   ALTER DATABASE postgres SET app.supabase_url = 'https://<ref>.supabase.co';
--   ALTER DATABASE postgres SET app.webhook_secret = '<secret>';

-- Ensure pg_net is available (idempotent — already enabled in local stack)
create extension if not exists pg_net with schema extensions;

-- ---------------------------------------------------------------------------
-- Shared trigger function
-- ---------------------------------------------------------------------------

create or replace function public.notify_send_notification()
returns trigger
language plpgsql
security definer
set search_path = public, net, extensions
as $$
declare
  base_url text;
  webhook_secret text;
  payload jsonb;
  edge_function_url text;
begin
  -- Read environment-specific config with local-dev fallbacks
  base_url := coalesce(
    current_setting('app.supabase_url', true),
    'http://host.docker.internal:54321'
  );
  webhook_secret := coalesce(
    current_setting('app.webhook_secret', true),
    ''
  );

  edge_function_url := base_url || '/functions/v1/send-notification';

  -- Construct the WebhookPayload shape matching index.ts:17-23
  payload := jsonb_build_object(
    'type', TG_OP,
    'table', TG_TABLE_NAME,
    'schema', TG_TABLE_SCHEMA,
    'record', to_jsonb(NEW),
    'old_record', case
      when TG_OP = 'UPDATE' then to_jsonb(OLD)
      else '{}'::jsonb
    end
  );

  -- Dispatch async via pg_net (non-blocking — does not hold the transaction)
  perform net.http_post(
    url := edge_function_url,
    body := payload,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', webhook_secret
    ),
    timeout_milliseconds := 5000
  );

  return NEW;
end;
$$;

-- ---------------------------------------------------------------------------
-- Triggers — three one-liners attaching the shared function
-- ---------------------------------------------------------------------------

-- Kudos: fire on every INSERT
create trigger notify_kudos_insert
  after insert on public.kudos
  for each row
  execute function public.notify_send_notification();

-- Comments: fire on every INSERT
create trigger notify_comments_insert
  after insert on public.comments
  for each row
  execute function public.notify_send_notification();

-- Follows: fire only when status transitions from 'pending' to 'accepted'
create trigger notify_follows_accepted
  after update on public.follows
  for each row
  when (OLD.status = 'pending' and NEW.status = 'accepted')
  execute function public.notify_send_notification();
