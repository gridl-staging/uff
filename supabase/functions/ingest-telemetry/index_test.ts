import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import type { IngestTelemetryDependencies } from "./index.ts";
import { handleIngestTelemetryRequest } from "./index.ts";
import {
  buildIngestRequest,
  createMockIngestClient,
  createSingleClientFactory,
  MOCK_SUPABASE_CONFIG,
  withEnvVarGuard,
} from "./test_support.ts";

const VALID_AUTH_HEADER = "Bearer test-token";

async function assertJsonResponse(
  response: Response,
  status: number,
  body: Record<string, unknown>,
): Promise<void> {
  assertEquals(response.status, status);
  assertEquals(await response.json(), body);
}

function buildAuthenticatedDeps(
  options: {
    client?: ReturnType<typeof createMockIngestClient>;
    getAuthUserFn?: IngestTelemetryDependencies["getAuthUserFn"];
  } = {},
) {
  const client = options.client ?? createMockIngestClient();
  const factory = createSingleClientFactory(client);

  return {
    client,
    factory,
    deps: {
      createClientFn: factory.createClientFn,
      loadConfigFn: () => MOCK_SUPABASE_CONFIG,
      getAuthUserFn: options.getAuthUserFn,
    } satisfies IngestTelemetryDependencies,
  };
}

// ── Request/auth seam tests ─────────────────────────────────────────

Deno.test("OPTIONS returns 204 with CORS headers", async () => {
  const response = await handleIngestTelemetryRequest(
    buildIngestRequest("OPTIONS"),
  );

  assertEquals(response.status, 204);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), "*");
  assertEquals(
    response.headers.get("Access-Control-Allow-Methods"),
    "POST, OPTIONS",
  );
  assertEquals(
    response.headers.get("Access-Control-Allow-Headers"),
    "Authorization, Content-Type, apikey",
  );
});

Deno.test("non-POST returns 405", async () => {
  const response = await handleIngestTelemetryRequest(
    buildIngestRequest("GET"),
  );
  await assertJsonResponse(response, 405, { error: "Method not allowed" });
});

Deno.test("PUT returns 405", async () => {
  const response = await handleIngestTelemetryRequest(
    buildIngestRequest("PUT"),
  );
  await assertJsonResponse(response, 405, { error: "Method not allowed" });
});

Deno.test("missing Authorization returns 401", async () => {
  const response = await handleIngestTelemetryRequest(
    buildIngestRequest("POST"),
  );
  await assertJsonResponse(response, 401, {
    error: "Missing or invalid authorization",
  });
});

Deno.test("non-Bearer Authorization returns 401", async () => {
  const response = await handleIngestTelemetryRequest(
    buildIngestRequest("POST", "Basic abc123"),
  );
  await assertJsonResponse(response, 401, {
    error: "Missing or invalid authorization",
  });
});

Deno.test("empty Bearer token returns 401", async () => {
  const response = await handleIngestTelemetryRequest(
    buildIngestRequest("POST", "Bearer   "),
  );
  await assertJsonResponse(response, 401, {
    error: "Missing or invalid authorization",
  });
});

Deno.test("missing env config returns 500", async () => {
  await withEnvVarGuard(async () => {
    const response = await handleIngestTelemetryRequest(
      buildIngestRequest("POST", VALID_AUTH_HEADER, { eventId: "e1" }),
      { loadConfigFn: () => null },
    );
    await assertJsonResponse(response, 500, {
      error: "Function configuration is incomplete",
    });
  });
});

Deno.test("expired/invalid JWT returns 401", async () => {
  const { deps } = buildAuthenticatedDeps({
    getAuthUserFn: async () => ({
      data: { user: null },
      error: { message: "jwt expired" },
    }),
  });
  const response = await handleIngestTelemetryRequest(
    buildIngestRequest("POST", VALID_AUTH_HEADER, { eventId: "e1" }),
    deps,
  );
  await assertJsonResponse(response, 401, {
    error: "Invalid or expired token",
  });
});

Deno.test("normalized bearer token forwarded to createClient", async () => {
  const { factory, deps } = buildAuthenticatedDeps({
    getAuthUserFn: async () => ({
      data: { user: null },
      error: { message: "jwt expired" },
    }),
  });

  await handleIngestTelemetryRequest(
    buildIngestRequest("POST", "  bearer   my-token-value   ", {
      eventId: "e1",
    }),
    deps,
  );

  assertEquals(factory.calls.length, 1);
  assertEquals(factory.calls[0]?.options, {
    global: {
      headers: { Authorization: "Bearer my-token-value" },
    },
  });
});

// ── Insert path tests ───────────────────────────────────────────────

const SAMPLE_EVENT = {
  eventId: "evt-abc-123",
  capturedAt: "2026-03-26T10:00:00.000Z",
  context: { appVersion: "1.0.0", platform: "ios" },
  metadata: { errorType: "StateError", message: "Bad state" },
  breadcrumbs: [{ timestamp: "2026-03-26T09:59:50.000Z", message: "init" }],
  // Client retry bookkeeping — must NOT be stored server-side
  attemptCount: 3,
  lastAttemptStatus: "network_error",
  lastAttemptedAt: "2026-03-26T09:59:55.000Z",
};

Deno.test("authenticated insert maps camelCase to snake_case and omits retry fields", async () => {
  const client = createMockIngestClient({ authUserId: "user-abc" });
  const { deps } = buildAuthenticatedDeps({ client });

  const response = await handleIngestTelemetryRequest(
    buildIngestRequest("POST", VALID_AUTH_HEADER, SAMPLE_EVENT),
    deps,
  );

  await assertJsonResponse(response, 200, { success: true });

  // Verify upsert was called with correct table and snake_case mapping
  assertEquals(client._upsertCalls.length, 1);
  const call = client._upsertCalls[0];
  assertEquals(call.table, "telemetry_events");
  assertEquals(call.options, {
    onConflict: "user_id,event_id",
    ignoreDuplicates: true,
  });
  assertEquals(call.rows, [
    {
      event_id: "evt-abc-123",
      captured_at: "2026-03-26T10:00:00.000Z",
      context: { appVersion: "1.0.0", platform: "ios" },
      metadata: {
        errorType: "StateError",
        message: "Bad state",
      },
      breadcrumbs: [
        { timestamp: "2026-03-26T09:59:50.000Z", message: "init" },
      ],
    },
  ]);
});

Deno.test("duplicate eventId upsert returns success (idempotent)", async () => {
  // First insert succeeds normally
  const client = createMockIngestClient({ authUserId: "user-abc" });
  const { deps } = buildAuthenticatedDeps({ client });

  const firstResponse = await handleIngestTelemetryRequest(
    buildIngestRequest("POST", VALID_AUTH_HEADER, SAMPLE_EVENT),
    deps,
  );
  await assertJsonResponse(firstResponse, 200, { success: true });

  // Second insert with the same eventId also returns success (upsert semantics)
  const secondResponse = await handleIngestTelemetryRequest(
    buildIngestRequest("POST", VALID_AUTH_HEADER, SAMPLE_EVENT),
    deps,
  );
  await assertJsonResponse(secondResponse, 200, { success: true });
  assertEquals(client._upsertCalls.length, 2);
});

Deno.test("upsert error returns 500", async () => {
  const client = createMockIngestClient({
    authUserId: "user-abc",
    upsertHandler: () => ({
      data: null,
      error: { message: "insert failed" },
    }),
  });
  const { deps } = buildAuthenticatedDeps({ client });

  const response = await handleIngestTelemetryRequest(
    buildIngestRequest("POST", VALID_AUTH_HEADER, SAMPLE_EVENT),
    deps,
  );
  await assertJsonResponse(response, 500, {
    error: "Failed to store telemetry event",
  });
});

Deno.test("missing eventId in body returns 400", async () => {
  const { deps } = buildAuthenticatedDeps();

  const response = await handleIngestTelemetryRequest(
    buildIngestRequest("POST", VALID_AUTH_HEADER, {
      capturedAt: "2026-03-26T10:00:00.000Z",
    }),
    deps,
  );
  await assertJsonResponse(response, 400, {
    error: "Missing required field: eventId",
  });
});

Deno.test("missing capturedAt in body returns 400", async () => {
  const { deps } = buildAuthenticatedDeps();

  const response = await handleIngestTelemetryRequest(
    buildIngestRequest("POST", VALID_AUTH_HEADER, { eventId: "e1" }),
    deps,
  );
  await assertJsonResponse(response, 400, {
    error: "Missing required field: capturedAt",
  });
});

Deno.test("non-object JSON body returns 400", async () => {
  const { deps } = buildAuthenticatedDeps();

  const response = await handleIngestTelemetryRequest(
    new Request("http://localhost/ingest-telemetry", {
      method: "POST",
      headers: {
        Authorization: VALID_AUTH_HEADER,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(["not", "an", "object"]),
    }),
    deps,
  );

  await assertJsonResponse(response, 400, {
    error: "JSON body must be an object",
  });
});

Deno.test("oversized JSON body returns 413", async () => {
  const { deps } = buildAuthenticatedDeps();
  const oversizedEvent = {
    eventId: "evt-oversized",
    capturedAt: "2026-03-26T10:00:00.000Z",
    metadata: {
      message: "a".repeat(70 * 1024),
    },
  };

  const response = await handleIngestTelemetryRequest(
    buildIngestRequest("POST", VALID_AUTH_HEADER, oversizedEvent),
    deps,
  );

  await assertJsonResponse(response, 413, {
    error: "Telemetry payload too large",
  });
});

Deno.test("malformed JSON body returns 400", async () => {
  const { deps } = buildAuthenticatedDeps();

  const request = new Request("http://localhost/ingest-telemetry", {
    method: "POST",
    headers: {
      Authorization: VALID_AUTH_HEADER,
      "Content-Type": "application/json",
    },
    body: "not-json",
  });

  const response = await handleIngestTelemetryRequest(request, deps);
  await assertJsonResponse(response, 400, { error: "Invalid JSON body" });
});
