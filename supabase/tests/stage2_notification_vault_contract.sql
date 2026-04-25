\set ON_ERROR_STOP on

-- Stage 2 notification Vault contract verification.
-- Confirms:
--   1. The supabase_vault extension is installed.
--   2. vault.create_secret() inserts a secret.
--   3. vault.decrypted_secrets returns the exact decrypted value.
--   4. Test cleanup removes the inserted secret.

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

select pg_temp.assert_true(
  exists (select 1 from pg_extension where extname = 'supabase_vault'),
  'supabase_vault extension must be installed'
);

do $$
declare
  contract_secret_id uuid;
  decrypted_value text;
begin
  contract_secret_id := vault.create_secret(
    'stage2-notification-vault-contract',
    null,
    'Temporary contract secret for notification Vault verification'
  );

  select decrypted_secret
    into decrypted_value
  from vault.decrypted_secrets
  where id = contract_secret_id;

  perform pg_temp.assert_true(
    decrypted_value = 'stage2-notification-vault-contract',
    'vault.decrypted_secrets must return the exact inserted secret value'
  );

  delete from vault.secrets
  where id = contract_secret_id;

  perform pg_temp.assert_true(
    not exists (select 1 from vault.secrets where id = contract_secret_id),
    'temporary contract secret must be cleaned up'
  );
end;
$$;

do $$ begin raise notice 'Stage 2 notification Vault contract verification: ALL PASSED'; end $$;
