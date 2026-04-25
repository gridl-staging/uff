import { assertEquals } from "@std/assert";
import { normalizeRetrievalCandidateDraft } from "./retrieval_contract.ts";

Deno.test("normalizeRetrievalCandidateDraft accepts padded draft and trims canonical fields", () => {
  const fixture = {
    name: "  Portland Running Club  ",
    city: "  Portland  ",
    state: "  OR  ",
    country: "  US  ",
    sourceId: "  rrca:portland-running-club  ",
    candidate_source_url: "  https://example.com/clubs/portland-running-club  ",
    evidence_ref: "  rrca:club/portland-running-club  ",
    retrieved_at: "  2026-04-20T10:15:00.000Z  ",
    retrieval_provider: "  rrca  ",
    // Stage 1 confirmed this optional ranking signal field name.
    confidenceScore: 0.74,
    unexpectedProperty: "do-not-copy",
  };

  const result = normalizeRetrievalCandidateDraft(fixture);

  assertEquals(result, {
    ok: true,
    candidate: {
      name: "Portland Running Club",
      city: "Portland",
      state: "OR",
      country: "US",
      sourceId: "rrca:portland-running-club",
      candidate_source_url: "https://example.com/clubs/portland-running-club",
      evidence_ref: "rrca:club/portland-running-club",
      retrieved_at: "2026-04-20T10:15:00.000Z",
      retrieval_provider: "rrca",
      confidenceScore: 0.74,
    },
  });
});

Deno.test("normalizeRetrievalCandidateDraft rejects draft without evidence_ref", () => {
  const fixture = {
    name: "Portland Running Club",
    city: "Portland",
    state: "OR",
    country: "US",
    sourceId: "  rrca:missing-evidence  ",
    candidate_source_url: "https://example.com/clubs/portland-running-club",
    retrieved_at: "2026-04-20T10:15:00.000Z",
    retrieval_provider: "rrca",
    // Unknown properties must not leak into the rejection result.
    confidenceScore: 0.74,
    unexpectedProperty: "do-not-copy",
  };

  const result = normalizeRetrievalCandidateDraft(fixture);

  assertEquals(result, {
    ok: false,
    reason: "missing_evidence_ref",
    sourceId: "rrca:missing-evidence",
  });
});

Deno.test("normalizeRetrievalCandidateDraft rejects whitespace-only evidence_ref", () => {
  const fixture = {
    name: "Portland Running Club",
    city: "Portland",
    state: "OR",
    country: "US",
    sourceId: "  rrca:whitespace-evidence  ",
    candidate_source_url: "https://example.com/clubs/portland-running-club",
    evidence_ref: "    ",
    retrieved_at: "2026-04-20T10:15:00.000Z",
    retrieval_provider: "rrca",
    // Unknown properties must not leak into the rejection result.
    confidenceScore: 0.74,
    unexpectedProperty: "do-not-copy",
  };

  const result = normalizeRetrievalCandidateDraft(fixture);

  assertEquals(result, {
    ok: false,
    reason: "missing_evidence_ref",
    sourceId: "rrca:whitespace-evidence",
  });
});
