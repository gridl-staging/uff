-- Move hosted notification trigger config from custom app.* GUCs into Vault.
--
-- Hosted Supabase blocks ALTER DATABASE/ALTER ROLE SET for custom app.*
-- parameters, so the trigger now reads Vault first and only falls back to the
-- legacy GUCs for local dev and older environments.

create extension if not exists supabase_vault with schema vault;

create or replace function public.notify_send_notification()
returns trigger
language plpgsql
security definer
set search_path = public, vault, net, extensions
as $$
declare
  vault_base_url text;
  vault_webhook_secret text;
  base_url text;
  webhook_secret text;
  payload jsonb;
  edge_function_url text;
begin
  -- Hosted Supabase rejects persistent custom app.* settings, so Vault is the
  -- durable source of truth. Keep the legacy GUC fallback for local dev.
  select decrypted_secret
    into vault_base_url
  from vault.decrypted_secrets
  where name = 'supabase_url'
  order by updated_at desc nulls last, created_at desc
  limit 1;

  select decrypted_secret
    into vault_webhook_secret
  from vault.decrypted_secrets
  where name = 'webhook_secret'
  order by updated_at desc nulls last, created_at desc
  limit 1;

  base_url := coalesce(
    vault_base_url,
    current_setting('app.supabase_url', true),
    'http://host.docker.internal:54321'
  );
  webhook_secret := coalesce(
    vault_webhook_secret,
    current_setting('app.webhook_secret', true),
    ''
  );

  edge_function_url := base_url || '/functions/v1/send-notification';

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
