-- Stage 3 discovery provenance/freshness persistence slice.
-- Adds nullable columns so existing rows remain valid.

alter table public.clubs
  add column source_adapter text,
  add column discovered_at timestamptz,
  add column last_refreshed_at timestamptz,
  add column confidence_score double precision,
  add column evidence_ref text,
  add column stale_after timestamptz;
