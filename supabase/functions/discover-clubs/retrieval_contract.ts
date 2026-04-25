import type {
  RetrievalCandidate,
  RetrievalCandidateDraft,
  RetrievalCandidateNormalizationResult,
} from "./types.ts";

/**
 * Normalizes the retrieval contract draft into an explicit canonical candidate.
 * Unknown properties are dropped by explicit field selection.
 */
export function normalizeRetrievalCandidateDraft(
  draft: RetrievalCandidateDraft,
): RetrievalCandidateNormalizationResult {
  const name = draft.name.trim();
  const city = draft.city.trim();
  const state = draft.state.trim();
  const country = draft.country.trim();
  const sourceId = draft.sourceId.trim();
  const candidateSourceUrl = draft.candidate_source_url.trim();
  const evidenceRef = (draft.evidence_ref ?? "").trim();
  const retrievedAt = draft.retrieved_at.trim();
  const retrievalProvider = draft.retrieval_provider.trim();

  if (evidenceRef.length === 0) {
    return {
      ok: false,
      reason: "missing_evidence_ref",
      sourceId,
    };
  }

  const candidate: RetrievalCandidate = {
    name,
    city,
    state,
    country,
    sourceId,
    candidate_source_url: candidateSourceUrl,
    evidence_ref: evidenceRef,
    retrieved_at: retrievedAt,
    retrieval_provider: retrievalProvider,
  };

  if (draft.confidenceScore !== undefined) {
    candidate.confidenceScore = draft.confidenceScore;
  }

  return {
    ok: true,
    candidate,
  };
}
