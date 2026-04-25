import { assertEquals, assertStringIncludes } from "@std/assert";
import {
  handleDiscoverClubsRequest,
  mapClubToInsertRow,
  runPipeline,
  validateClub,
} from "./index.ts";
import type { NormalizedClub, SourceAdapter } from "./types.ts";
import {
  buildDiscoverRequest,
  createMockDiscoverClient,
  createServiceClientFactory,
} from "./test_support.ts";

const TEST_SERVICE_ROLE_KEY = "service-role-test-key";

// ── Helpers ─────────────────────────────────────────────────────────

function validClub(overrides: Partial<NormalizedClub> = {}): NormalizedClub {
  return {
    name: "Portland Running Club",
    city: "Portland",
    stateRegion: "OR",
    country: "US",
    sourceId: "rrca:portland-running-club",
    source: "auto_discovered",
    ...overrides,
  };
}

function validClubWithProvenance(
  overrides: Partial<NormalizedClub> = {},
): NormalizedClub {
  return {
    ...validClub(),
    sourceAdapter: "rrca",
    discoveredAt: "2026-04-01T12:00:00.000Z",
    lastRefreshedAt: "2026-04-03T12:00:00.000Z",
    confidenceScore: 0.74,
    evidenceRef: "rrca:club/portland-running-club",
    staleAfter: "2026-05-03T12:00:00.000Z",
    ...overrides,
  };
}

function stubAdapter(clubs: NormalizedClub[]): SourceAdapter {
  return {
    name: "test",
    discover: () => Promise.resolve(clubs),
  };
}

function buildAuthorizedDiscoverRequest(
  method: string,
  params?: Record<string, string>,
): Request {
  return buildDiscoverRequest(method, params, {
    apikey: TEST_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${TEST_SERVICE_ROLE_KEY}`,
  });
}

// ── Validation tests ────────────────────────────────────────────────

Deno.test("validateClub: valid club passes", () => {
  const error = validateClub(validClub());
  assertEquals(error, null);
});

Deno.test("validateClub: missing name rejects", () => {
  const error = validateClub(validClub({ name: "" }));
  assertEquals(error, "Missing required field: name");
});

Deno.test("validateClub: whitespace-only name rejects", () => {
  const error = validateClub(validClub({ name: "   " }));
  assertEquals(error, "Missing required field: name");
});

Deno.test("validateClub: missing city rejects", () => {
  const error = validateClub(validClub({ city: "" }));
  assertEquals(error, "Missing required field: city");
});

Deno.test("validateClub: missing sourceId rejects", () => {
  const error = validateClub(validClub({ sourceId: "" }));
  assertEquals(error, "Missing required field: sourceId");
});

// ── mapClubToInsertRow tests ────────────────────────────────────────

Deno.test("mapClubToInsertRow: maps camelCase to snake_case with correct defaults", () => {
  const club = validClub({
    description: "A great club",
    locationLat: 45.52,
    locationLng: -122.68,
    sourceUrl: "https://example.com",
  });
  const row = mapClubToInsertRow(club);
  assertEquals(row, {
    name: "Portland Running Club",
    description: "A great club",
    city: "Portland",
    state_region: "OR",
    country: "US",
    location_lat: 45.52,
    location_lng: -122.68,
    source: "auto_discovered",
    source_url: "https://example.com",
    source_id: "rrca:portland-running-club",
    source_adapter: null,
    discovered_at: null,
    last_refreshed_at: null,
    confidence_score: null,
    evidence_ref: null,
    stale_after: null,
    creator_id: null,
    claimed_by: null,
  });
});

Deno.test("mapClubToInsertRow: optional fields default to null", () => {
  const row = mapClubToInsertRow(validClub());
  assertEquals(row.description, null);
  assertEquals(row.location_lat, null);
  assertEquals(row.location_lng, null);
  assertEquals(row.source_url, null);
  assertEquals(row.source_adapter, null);
  assertEquals(row.discovered_at, null);
  assertEquals(row.last_refreshed_at, null);
  assertEquals(row.confidence_score, null);
  assertEquals(row.evidence_ref, null);
  assertEquals(row.stale_after, null);
});

Deno.test("mapClubToInsertRow: writes provenance and freshness metadata fields", () => {
  const row = mapClubToInsertRow(validClubWithProvenance());

  assertEquals(row.source_adapter, "rrca");
  assertEquals(row.discovered_at, "2026-04-01T12:00:00.000Z");
  assertEquals(row.last_refreshed_at, "2026-04-03T12:00:00.000Z");
  assertEquals(row.confidence_score, 0.74);
  assertEquals(row.evidence_ref, "rrca:club/portland-running-club");
  assertEquals(row.stale_after, "2026-05-03T12:00:00.000Z");
  assertEquals(row.source, "auto_discovered");
  assertEquals(row.creator_id, null);
  assertEquals(row.claimed_by, null);
});

// ── Pipeline tests ──────────────────────────────────────────────────

Deno.test("pipeline: new club with no match returns inserted count 1", async () => {
  const client = createMockDiscoverClient();
  const result = await runPipeline(client, [validClub()], "test");

  assertEquals(result.source, "test");
  assertEquals(result.found, 1);
  assertEquals(result.inserted, 1);
  assertEquals(result.updated, 0);
  assertEquals(result.errors.length, 0);

  // New records should be inserted directly (no invalid source_id conflict target).
  assertEquals(client._insertCalls.length, 1);
  assertEquals(client._insertCalls[0].table, "clubs");
  assertEquals(client._updateCalls.length, 0);
  assertEquals(client._upsertCalls.length, 0);
});

Deno.test("pipeline: existing club with same source_id returns updated count", async () => {
  const client = createMockDiscoverClient({
    selectResults: {
      clubs: [{ id: "existing-id", source_id: "rrca:portland-running-club" }],
    },
  });

  const result = await runPipeline(client, [validClub()], "test");

  assertEquals(result.found, 1);
  assertEquals(result.inserted, 0);
  assertEquals(result.updated, 1);
  assertEquals(result.errors.length, 0);
  assertEquals(client._updateCalls.length, 1);
  assertEquals(client._updateCalls[0].filters, [{
    column: "id",
    value: "existing-id",
  }]);
  assertEquals(client._insertCalls.length, 0);
  assertEquals(client._upsertCalls.length, 0);
});

Deno.test("pipeline: fallback name+city dedup updates matched row id", async () => {
  const client = createMockDiscoverClient({
    selectResults: {
      clubs: [{
        id: "existing-id",
        name: "Portland Running Club",
        city: "Portland",
        source: "auto_discovered",
        source_id: "rrca:old-id",
      }],
    },
  });

  const result = await runPipeline(
    client,
    [validClub({ sourceId: "rrca:new-id" })],
    "test",
  );

  assertEquals(result.inserted, 0);
  assertEquals(result.updated, 1);
  assertEquals(result.errors.length, 0);
  assertEquals(client._updateCalls.length, 1);
  assertEquals(client._updateCalls[0].filters, [{
    column: "id",
    value: "existing-id",
  }]);
  assertEquals(client._insertCalls.length, 0);
  assertEquals(client._upsertCalls.length, 0);
});

Deno.test("pipeline: fallback name+city ignores user-created clubs", async () => {
  const client = createMockDiscoverClient({
    selectResults: {
      clubs: [{
        id: "user-created-id",
        name: "Portland Running Club",
        city: "Portland",
        source: "user_created",
      }],
    },
  });

  const result = await runPipeline(
    client,
    [validClub({ sourceId: "rrca:new-id" })],
    "test",
  );

  assertEquals(result.inserted, 1);
  assertEquals(result.updated, 0);
  assertEquals(result.errors.length, 0);
  assertEquals(client._updateCalls.length, 0);
  assertEquals(client._insertCalls.length, 1);
});

Deno.test("pipeline: invalid club records error, skips upsert", async () => {
  const client = createMockDiscoverClient();
  const badClub = validClub({ name: "", sourceId: "rrca:bad" });

  const result = await runPipeline(client, [badClub], "test");

  assertEquals(result.found, 1);
  assertEquals(result.inserted, 0);
  assertEquals(result.updated, 0);
  assertEquals(result.errors.length, 1);
  assertStringIncludes(result.errors[0], "Missing required field: name");

  // Invalid records should not issue writes.
  assertEquals(client._insertCalls.length, 0);
  assertEquals(client._updateCalls.length, 0);
  assertEquals(client._upsertCalls.length, 0);
});

Deno.test("pipeline: dedup lookup error records error and skips writes", async () => {
  const client = createMockDiscoverClient({
    selectError: { message: "select failed" },
  });

  const result = await runPipeline(client, [validClub()], "test");

  assertEquals(result.inserted, 0);
  assertEquals(result.updated, 0);
  assertEquals(result.errors.length, 1);
  assertStringIncludes(result.errors[0], "source_id dedup lookup failed");
  assertEquals(client._insertCalls.length, 0);
  assertEquals(client._updateCalls.length, 0);
  assertEquals(client._upsertCalls.length, 0);
});

Deno.test("pipeline: insert error records error in result", async () => {
  const client = createMockDiscoverClient({
    insertError: { message: "permission denied" },
  });

  const result = await runPipeline(client, [validClub()], "test");

  assertEquals(result.inserted, 0);
  assertEquals(result.updated, 0);
  assertEquals(result.errors.length, 1);
  assertStringIncludes(result.errors[0], "permission denied");
});

Deno.test("pipeline: update error records error in result", async () => {
  const client = createMockDiscoverClient({
    selectResults: {
      clubs: [{ id: "existing-id", source_id: "rrca:portland-running-club" }],
    },
    updateError: { message: "write failed" },
  });

  const result = await runPipeline(client, [validClub()], "test");

  assertEquals(result.inserted, 0);
  assertEquals(result.updated, 0);
  assertEquals(result.errors.length, 1);
  assertStringIncludes(result.errors[0], "write failed");
});

Deno.test("pipeline: updates preserve ownership and source fields", async () => {
  const client = createMockDiscoverClient({
    selectResults: {
      clubs: [{ id: "existing-id", source_id: "rrca:portland-running-club" }],
    },
  });

  const result = await runPipeline(client, [validClub()], "test");

  assertEquals(result.inserted, 0);
  assertEquals(result.updated, 1);
  assertEquals(result.errors.length, 0);
  assertEquals(client._updateCalls.length, 1);
  assertEquals(client._updateCalls[0].values, {
    name: "Portland Running Club",
    city: "Portland",
    state_region: "OR",
    country: "US",
    source_id: "rrca:portland-running-club",
  });
});

Deno.test("pipeline: updates do not clear existing optional metadata when adapter omits it", async () => {
  const client = createMockDiscoverClient({
    selectResults: {
      clubs: [{
        id: "existing-id",
        source_id: "rrca:portland-running-club",
        description: "Existing description",
        location_lat: 45.52,
        location_lng: -122.68,
        source_url: "https://existing.example.com",
      }],
    },
  });

  const result = await runPipeline(client, [validClub()], "test");

  assertEquals(result.inserted, 0);
  assertEquals(result.updated, 1);
  assertEquals(result.errors.length, 0);
  assertEquals(client._updateCalls.length, 1);
  assertEquals(client._updateCalls[0].values.description, undefined);
  assertEquals(client._updateCalls[0].values.location_lat, undefined);
  assertEquals(client._updateCalls[0].values.location_lng, undefined);
  assertEquals(client._updateCalls[0].values.source_url, undefined);
});

Deno.test("pipeline: rediscovery refreshes provenance fields without changing ownership fields", async () => {
  const client = createMockDiscoverClient({
    selectResults: {
      clubs: [{
        id: "existing-id",
        source_id: "rrca:portland-running-club",
        source: "auto_discovered",
        creator_id: null,
        claimed_by: null,
        description: "Existing description",
        location_lat: 45.52,
        location_lng: -122.68,
        source_url: "https://existing.example.com",
      }],
    },
  });

  const result = await runPipeline(
    client,
    [validClubWithProvenance()],
    "test",
  );

  assertEquals(result.inserted, 0);
  assertEquals(result.updated, 1);
  assertEquals(result.errors.length, 0);
  assertEquals(client._updateCalls.length, 1);
  assertEquals(client._updateCalls[0].values, {
    name: "Portland Running Club",
    city: "Portland",
    state_region: "OR",
    country: "US",
    source_id: "rrca:portland-running-club",
    source_adapter: "rrca",
    discovered_at: "2026-04-01T12:00:00.000Z",
    last_refreshed_at: "2026-04-03T12:00:00.000Z",
    confidence_score: 0.74,
    evidence_ref: "rrca:club/portland-running-club",
    stale_after: "2026-05-03T12:00:00.000Z",
  });
  assertEquals("source" in client._updateCalls[0].values, false);
  assertEquals("creator_id" in client._updateCalls[0].values, false);
  assertEquals("claimed_by" in client._updateCalls[0].values, false);
  assertEquals(client._updateCalls[0].values.description, undefined);
  assertEquals(client._updateCalls[0].values.location_lat, undefined);
  assertEquals(client._updateCalls[0].values.location_lng, undefined);
  assertEquals(client._updateCalls[0].values.source_url, undefined);
});

Deno.test("pipeline: mixed valid and invalid clubs processes correctly", async () => {
  const client = createMockDiscoverClient();
  const clubs = [
    validClub(),
    validClub({ name: "", sourceId: "rrca:invalid" }),
    validClub({
      name: "Austin Runners",
      city: "Austin",
      sourceId: "rrca:austin-runners",
    }),
  ];

  const result = await runPipeline(client, clubs, "test");

  assertEquals(result.found, 3);
  assertEquals(result.inserted, 2);
  assertEquals(result.updated, 0);
  assertEquals(result.errors.length, 1);
  assertEquals(client._insertCalls.length, 2);
  assertEquals(client._updateCalls.length, 0);
  assertEquals(client._upsertCalls.length, 0);
});

Deno.test("pipeline: fallback name+city dedup escapes wildcard characters", async () => {
  const client = createMockDiscoverClient();

  const result = await runPipeline(
    client,
    [
      validClub({
        sourceId: "rrca:run-percent",
        name: "Run_%",
        city: "Port_land%",
      }),
    ],
    "test",
  );

  assertEquals(result.inserted, 1);
  assertEquals(result.errors.length, 0);
  assertEquals(client._selectQueries.length, 2);
  assertEquals(client._selectQueries[1], {
    table: "clubs",
    filters: [
      { column: "source", value: "auto_discovered" },
      { column: "name", value: "ilike:Run\\_\\%" },
      { column: "city", value: "ilike:Port\\_land\\%" },
    ],
  });
});

// ── HTTP handler tests ──────────────────────────────────────────────

Deno.test("OPTIONS returns 204 with CORS headers", async () => {
  const response = await handleDiscoverClubsRequest(
    buildDiscoverRequest("OPTIONS"),
  );
  assertEquals(response.status, 204);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("GET returns 405", async () => {
  const response = await handleDiscoverClubsRequest(
    buildDiscoverRequest("GET"),
  );
  assertEquals(response.status, 405);
  assertEquals(await response.json(), { error: "Method not allowed" });
});

Deno.test("POST with no adapters returns 400", async () => {
  const client = createMockDiscoverClient();
  const factory = createServiceClientFactory(client);
  const response = await handleDiscoverClubsRequest(
    buildAuthorizedDiscoverRequest("POST"),
    {
      createServiceClient: factory.createServiceClient,
      adapters: [],
      getServiceRoleKey: () => TEST_SERVICE_ROLE_KEY,
    },
  );
  assertEquals(response.status, 400);
  assertEquals(await response.json(), {
    error: "No source adapters configured",
  });
});

Deno.test("POST without service-role authorization returns 401", async () => {
  const client = createMockDiscoverClient();
  const factory = createServiceClientFactory(client);
  const response = await handleDiscoverClubsRequest(
    buildDiscoverRequest("POST"),
    {
      createServiceClient: factory.createServiceClient,
      adapters: [stubAdapter([])],
      getServiceRoleKey: () => TEST_SERVICE_ROLE_KEY,
    },
  );
  assertEquals(response.status, 401);
  assertEquals(await response.json(), { error: "Unauthorized" });
  assertEquals(factory.calls, 0);
});

Deno.test("POST without injected adapters uses runtime defaults", async () => {
  const client = createMockDiscoverClient();
  const factory = createServiceClientFactory(client);
  const response = await handleDiscoverClubsRequest(
    buildAuthorizedDiscoverRequest("POST", { source: "not_registered" }),
    {
      createServiceClient: factory.createServiceClient,
      getServiceRoleKey: () => TEST_SERVICE_ROLE_KEY,
    },
  );

  assertEquals(response.status, 400);
  const body = await response.json();
  assertStringIncludes(body.error, "Unknown source: not_registered");
});

Deno.test("POST with unknown source returns 400", async () => {
  const client = createMockDiscoverClient();
  const factory = createServiceClientFactory(client);
  const response = await handleDiscoverClubsRequest(
    buildAuthorizedDiscoverRequest("POST", { source: "nonexistent" }),
    {
      createServiceClient: factory.createServiceClient,
      adapters: [stubAdapter([])],
      getServiceRoleKey: () => TEST_SERVICE_ROLE_KEY,
    },
  );
  assertEquals(response.status, 400);
  const body = await response.json();
  assertStringIncludes(body.error, "Unknown source: nonexistent");
});

Deno.test("POST runs adapter pipeline and returns results", async () => {
  const client = createMockDiscoverClient();
  const factory = createServiceClientFactory(client);
  const adapter = stubAdapter([validClub()]);

  const response = await handleDiscoverClubsRequest(
    buildAuthorizedDiscoverRequest("POST"),
    {
      createServiceClient: factory.createServiceClient,
      adapters: [adapter],
      getServiceRoleKey: () => TEST_SERVICE_ROLE_KEY,
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.results.length, 1);
  assertEquals(body.results[0].source, "test");
  assertEquals(body.results[0].inserted, 1);
  assertEquals(body.results[0].found, 1);
});

Deno.test("POST filters adapters by source param", async () => {
  const client = createMockDiscoverClient();
  const factory = createServiceClientFactory(client);
  const rrca = { ...stubAdapter([validClub()]), name: "rrca" };
  const google = {
    ...stubAdapter([validClub({ sourceId: "google:123" })]),
    name: "google_places",
  };

  const response = await handleDiscoverClubsRequest(
    buildAuthorizedDiscoverRequest("POST", { source: "rrca" }),
    {
      createServiceClient: factory.createServiceClient,
      adapters: [rrca, google],
      getServiceRoleKey: () => TEST_SERVICE_ROLE_KEY,
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  // Only rrca adapter should have run
  assertEquals(body.results.length, 1);
  assertEquals(body.results[0].source, "rrca");
});

Deno.test("POST handles adapter exception gracefully", async () => {
  const client = createMockDiscoverClient();
  const factory = createServiceClientFactory(client);
  const failingAdapter: SourceAdapter = {
    name: "broken",
    discover: () => Promise.reject(new Error("network timeout")),
  };

  const response = await handleDiscoverClubsRequest(
    buildAuthorizedDiscoverRequest("POST"),
    {
      createServiceClient: factory.createServiceClient,
      adapters: [failingAdapter],
      getServiceRoleKey: () => TEST_SERVICE_ROLE_KEY,
    },
  );

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.results.length, 1);
  assertEquals(body.results[0].found, 0);
  assertStringIncludes(body.results[0].errors[0], "network timeout");
});
