-- Stage 3: telemetry event storage boundary
--
-- Stores durable telemetry events received from the ingest-telemetry Edge
-- Function. Identity is derived from auth.uid() via column default — the Edge
-- Function never sets user_id. Client retry bookkeeping (attemptCount,
-- lastAttemptStatus, lastAttemptedAt) lives in the local SQLite TelemetryStore
-- and is intentionally excluded from this table.

create table public.telemetry_events (
  id uuid primary key default gen_random_uuid(),
  event_id text not null,
  user_id uuid not null default auth.uid(),
  captured_at timestamptz not null,
  received_at timestamptz not null default now(),
  context jsonb,
  metadata jsonb,
  breadcrumbs jsonb
);

-- Unique constraint scopes idempotent upserts to a single authenticated user.
-- event_id alone is not a safe global key because another user could collide
-- with or intentionally pre-claim the same client-generated id.
alter table public.telemetry_events
  add constraint telemetry_events_user_event_id_unique unique (user_id, event_id);

alter table public.telemetry_events enable row level security;

-- Only authenticated users may insert. No SELECT/UPDATE/DELETE granted —
-- telemetry is write-only from the client's perspective.
grant insert on public.telemetry_events to authenticated;

-- Safety-net policy: confirms the row's user_id matches the caller's JWT.
-- Since user_id defaults to auth.uid() and the Edge Function never sets it,
-- this policy should always pass for legitimate inserts.
create policy "telemetry_events_insert_own"
  on public.telemetry_events for insert
  to authenticated
  with check (auth.uid() = user_id);
