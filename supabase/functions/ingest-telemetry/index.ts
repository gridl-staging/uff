/**
 * @module Stub summary for /Users/stuart/parallel_development/uff_dev/mar26_pm_6_telemetry_and_infra_hardening/uff_dev/supabase/functions/ingest-telemetry/index.ts.
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface IngestSupabaseConfig {
  supabaseUrl: string;
  anonKey: string;
}

// deno-lint-ignore no-explicit-any
export type SupabaseClient = any;

export const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, apikey",
};
const MAX_REQUEST_BODY_BYTES = 64 * 1024;
const REQUIRED_BODY_FIELDS = ["eventId", "capturedAt"] as const;

export type CreateClientFn = (
  supabaseUrl: string,
  supabaseKey: string,
  options?: {
    global?: {
      headers?: Record<string, string>;
    };
  },
) => SupabaseClient;

export type GetAuthUserFn = (
  userClient: SupabaseClient,
) => Promise<{
  data: { user: { id: string } | null };
  error: { message: string } | null;
}>;

export interface IngestTelemetryDependencies {
  createClientFn?: CreateClientFn;
  loadConfigFn?: () => IngestSupabaseConfig | null;
  getAuthUserFn?: GetAuthUserFn;
}

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
    },
  });
}

function loadSupabaseConfig(): IngestSupabaseConfig | null {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !anonKey) {
    return null;
  }

  return { supabaseUrl, anonKey };
}

/**
 * TODO: Document normalizeBearerAuthorizationHeader.
 */
function normalizeBearerAuthorizationHeader(
  authHeader: string | null,
): string | null {
  if (!authHeader) {
    return null;
  }

  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return null;
  }

  const token = match[1].trim();
  if (!token) {
    return null;
  }

  return `Bearer ${token}`;
}

/**
 * Maps a QueuedTelemetryEvent.toJson() payload to the snake_case columns
 * expected by public.telemetry_events. Intentionally omits user_id (DB default)
 * and client retry bookkeeping fields.
 */
function mapEventToRow(
  body: Record<string, unknown>,
): Record<string, unknown> {
  return {
    event_id: body.eventId,
    captured_at: body.capturedAt,
    context: body.context ?? null,
    metadata: body.metadata ?? null,
    breadcrumbs: body.breadcrumbs ?? null,
  };
}

/**
 * TODO: Document parseRequestBody.
 */
async function parseRequestBody(
  req: Request,
): Promise<Record<string, unknown> | Response> {
  const rawBody = await req.text();
  if (new TextEncoder().encode(rawBody).length > MAX_REQUEST_BODY_BYTES) {
    return jsonResponse({ error: "Telemetry payload too large" }, 413);
  }

  let parsedBody: unknown;
  try {
    parsedBody = JSON.parse(rawBody);
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  if (
    parsedBody == null ||
    typeof parsedBody !== "object" ||
    Array.isArray(parsedBody)
  ) {
    return jsonResponse({ error: "JSON body must be an object" }, 400);
  }

  return parsedBody as Record<string, unknown>;
}

function findMissingRequiredField(
  body: Record<string, unknown>,
): (typeof REQUIRED_BODY_FIELDS)[number] | null {
  for (const fieldName of REQUIRED_BODY_FIELDS) {
    if (!body[fieldName]) {
      return fieldName;
    }
  }

  return null;
}

/**
 * TODO: Document handleIngestTelemetryRequest.
 */
export async function handleIngestTelemetryRequest(
  req: Request,
  deps: IngestTelemetryDependencies = {},
): Promise<Response> {
  const {
    createClientFn = createClient as CreateClientFn,
    loadConfigFn = loadSupabaseConfig,
    getAuthUserFn = (userClient: SupabaseClient) => userClient.auth.getUser(),
  } = deps;

  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: CORS_HEADERS,
    });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = normalizeBearerAuthorizationHeader(
    req.headers.get("Authorization"),
  );
  if (!authHeader) {
    return jsonResponse({ error: "Missing or invalid authorization" }, 401);
  }

  const config = loadConfigFn();
  if (!config) {
    return jsonResponse(
      { error: "Function configuration is incomplete" },
      500,
    );
  }

  // Create caller-scoped client — user_id derived from JWT, not request body
  const userClient = createClientFn(config.supabaseUrl, config.anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error: authError,
  } = await getAuthUserFn(userClient);

  if (authError || !user) {
    return jsonResponse({ error: "Invalid or expired token" }, 401);
  }

  // Parse and validate body
  const parsedBody = await parseRequestBody(req);
  if (parsedBody instanceof Response) {
    return parsedBody;
  }
  const body = parsedBody;

  const missingField = findMissingRequiredField(body);
  if (missingField) {
    return jsonResponse({ error: `Missing required field: ${missingField}` }, 400);
  }

  // Map camelCase payload to snake_case row, excluding retry bookkeeping
  const row = mapEventToRow(body);

  const { error: upsertError } = await userClient
    .from("telemetry_events")
    .upsert([row], { onConflict: "user_id,event_id", ignoreDuplicates: true });

  if (upsertError) {
    return jsonResponse({ error: "Failed to store telemetry event" }, 500);
  }

  return jsonResponse({ success: true }, 200);
}

if (import.meta.main) {
  Deno.serve(
    (req: Request): Promise<Response> => handleIngestTelemetryRequest(req),
  );
}
