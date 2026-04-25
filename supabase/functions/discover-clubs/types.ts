/**
 * Shared types for the discover-clubs edge function.
 *
 * NormalizedClub uses camelCase; the pipeline upsert maps to snake_case
 * DB columns (e.g. stateRegion → state_region).
 */

/** A club normalized from any external source, ready for validation and upsert. */
export interface NormalizedClub {
  name: string;
  description?: string;
  city: string;
  stateRegion: string;
  country: string;
  locationLat?: number;
  locationLng?: number;
  sourceUrl?: string;
  sourceAdapter?: string;
  discoveredAt?: string;
  lastRefreshedAt?: string;
  confidenceScore?: number;
  evidenceRef?: string;
  staleAfter?: string;
  sourceId: string;
  source: "auto_discovered";
}

/** Retrieval contract draft from adapters before deterministic normalization. */
export interface RetrievalCandidateDraft {
  name: string;
  city: string;
  state: string;
  country: string;
  sourceId: string;
  candidate_source_url: string;
  evidence_ref?: string;
  retrieved_at: string;
  retrieval_provider: string;
  confidenceScore?: number;
}

/** Canonical retrieval candidate accepted by the Stage 3 contract boundary. */
export interface RetrievalCandidate {
  name: string;
  city: string;
  state: string;
  country: string;
  sourceId: string;
  candidate_source_url: string;
  evidence_ref: string;
  retrieved_at: string;
  retrieval_provider: string;
  confidenceScore?: number;
}

/** Result for retrieval candidate normalization at the Stage 3 boundary. */
export type RetrievalCandidateNormalizationResult =
  | {
    ok: true;
    candidate: RetrievalCandidate;
  }
  | {
    ok: false;
    reason: "missing_evidence_ref";
    sourceId: string;
  };

/** Parameters for a discovery request. */
export interface DiscoverParams {
  city?: string;
  stateRegion?: string;
  source?: string;
}

/** Summary result from a discovery pipeline run. */
export interface DiscoverResult {
  source: string;
  found: number;
  inserted: number;
  updated: number;
  errors: string[];
}

/** A source adapter that fetches and normalizes clubs from one external source. */
export interface SourceAdapter {
  name: string;
  discover: (
    params: DiscoverParams,
    fetchFn?: typeof fetch,
  ) => Promise<NormalizedClub[]>;
}
