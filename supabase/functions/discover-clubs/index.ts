/**
 * @module Stub summary for index.ts.
 */
/**
 * discover-clubs edge function.
 *
 * Pipeline: fetch from external sources → normalize → validate → dedup → upsert.
 * Uses SUPABASE_SERVICE_ROLE_KEY to bypass RLS (auto-discovered clubs have
 * creator_id: null which the clubs_insert_creator policy rejects).
 */
import { createClient } from "@supabase/supabase-js";
import type {
  DiscoverParams,
  DiscoverResult,
  NormalizedClub,
  SourceAdapter,
} from "./types.ts";
import { googlePlacesAdapter } from "./adapters/google_places.ts";
import { rrcaAdapter } from "./adapters/rrca.ts";

// deno-lint-ignore no-explicit-any
export type SupabaseClient = any;

export const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, apikey",
};

export interface DiscoverClubsDependencies {
  createServiceClient?: () => SupabaseClient;
  adapters?: SourceAdapter[];
  getServiceRoleKey?: () => string | undefined;
}

const DEFAULT_ADAPTERS: SourceAdapter[] = [rrcaAdapter, googlePlacesAdapter];

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function createDefaultServiceClient(): SupabaseClient {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }
  return createClient(supabaseUrl, serviceRoleKey);
}

function readServiceRoleKey(
  deps: DiscoverClubsDependencies,
): string {
  const serviceRoleKey = deps.getServiceRoleKey
    ? deps.getServiceRoleKey()
    : Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceRoleKey) {
    throw new Error("Missing SUPABASE_SERVICE_ROLE_KEY");
  }
  return serviceRoleKey;
}

/**
 * TODO: Document requestHasServiceRoleAuthorization.
 */
function requestHasServiceRoleAuthorization(
  req: Request,
  serviceRoleKey: string,
): boolean {
  if (req.headers.get("apikey") == serviceRoleKey) {
    return true;
  }

  const authorizationHeader = req.headers.get("Authorization");
  if (authorizationHeader == null) {
    return false;
  }

  const bearerMatch = authorizationHeader.match(/^Bearer\s+(.+)$/i);
  return bearerMatch?.[1] == serviceRoleKey;
}

function escapeIlikeLiteral(value: string): string {
  return value
    .replaceAll("\\", "\\\\")
    .replaceAll("%", "\\%")
    .replaceAll("_", "\\_");
}

/** Validates a NormalizedClub has required fields. Returns error message or null. */
export function validateClub(club: NormalizedClub): string | null {
  if (!club.name || club.name.trim().length === 0) {
    return "Missing required field: name";
  }
  if (!club.city || club.city.trim().length === 0) {
    return "Missing required field: city";
  }
  if (!club.sourceId || club.sourceId.trim().length === 0) {
    return "Missing required field: sourceId";
  }
  return null;
}

/** Maps camelCase NormalizedClub to a full insert row. */
export function mapClubToInsertRow(
  club: NormalizedClub,
): Record<string, unknown> {
  return {
    name: club.name.trim(),
    description: club.description ?? null,
    city: club.city.trim(),
    state_region: club.stateRegion,
    country: club.country,
    location_lat: club.locationLat ?? null,
    location_lng: club.locationLng ?? null,
    source: "auto_discovered",
    source_url: club.sourceUrl ?? null,
    source_id: club.sourceId,
    source_adapter: club.sourceAdapter ?? null,
    discovered_at: club.discoveredAt ?? null,
    last_refreshed_at: club.lastRefreshedAt ?? null,
    confidence_score: club.confidenceScore ?? null,
    evidence_ref: club.evidenceRef ?? null,
    stale_after: club.staleAfter ?? null,
    creator_id: null,
    claimed_by: null,
  };
}

/**
 * Updates should preserve ownership and source classification on existing rows.
 * Re-discovery can refresh metadata and source identifiers, but it must not
 * reset claims, clear existing discovery metadata to null, or convert a
 * claimed/user-created record back to auto-discovered.
 */
function mapClubToUpdateRow(
  club: NormalizedClub,
): Record<string, unknown> {
  const row: Record<string, unknown> = {
    name: club.name.trim(),
    city: club.city.trim(),
    state_region: club.stateRegion,
    country: club.country,
    source_id: club.sourceId,
  };

  if (club.description !== undefined) {
    row.description = club.description;
  }
  if (club.locationLat !== undefined) {
    row.location_lat = club.locationLat;
  }
  if (club.locationLng !== undefined) {
    row.location_lng = club.locationLng;
  }
  if (club.sourceUrl !== undefined) {
    row.source_url = club.sourceUrl;
  }
  // Re-discovery can update provenance/freshness when the adapter provides it.
  // Omitted optional fields are intentionally left untouched in DB state.
  if (club.sourceAdapter !== undefined) {
    row.source_adapter = club.sourceAdapter;
  }
  if (club.discoveredAt !== undefined) {
    row.discovered_at = club.discoveredAt;
  }
  if (club.lastRefreshedAt !== undefined) {
    row.last_refreshed_at = club.lastRefreshedAt;
  }
  if (club.confidenceScore !== undefined) {
    row.confidence_score = club.confidenceScore;
  }
  if (club.evidenceRef !== undefined) {
    row.evidence_ref = club.evidenceRef;
  }
  if (club.staleAfter !== undefined) {
    row.stale_after = club.staleAfter;
  }

  return row;
}

/**
 * TODO: Document findExistingClubId.
 */
async function findExistingClubId(
  client: SupabaseClient,
  club: NormalizedClub,
): Promise<string | null> {
  // First: exact source_id match
  const { data: bySourceId, error: bySourceIdError } = await client
    .from("clubs")
    .select("id")
    .eq("source_id", club.sourceId);

  if (bySourceIdError) {
    throw new Error(
      `source_id dedup lookup failed — ${bySourceIdError.message}`,
    );
  }

  if (bySourceId && bySourceId.length > 0) {
    return bySourceId[0].id as string;
  }

  // Fallback: case-insensitive name+city
  const { data: byNameCity, error: byNameCityError } = await client
    .from("clubs")
    .select("id")
    .eq("source", "auto_discovered")
    .ilike("name", escapeIlikeLiteral(club.name.trim()))
    .ilike("city", escapeIlikeLiteral(club.city.trim()));

  if (byNameCityError) {
    throw new Error(
      `name+city dedup lookup failed — ${byNameCityError.message}`,
    );
  }

  if (byNameCity && byNameCity.length > 0) {
    return byNameCity[0].id as string;
  }

  return null;
}

/**
 * Core pipeline: validate, dedup, and upsert a batch of NormalizedClubs.
 * Returns a DiscoverResult summary.
 */
export async function runPipeline(
  client: SupabaseClient,
  clubs: NormalizedClub[],
  sourceName: string,
): Promise<DiscoverResult> {
  const result: DiscoverResult = {
    source: sourceName,
    found: clubs.length,
    inserted: 0,
    updated: 0,
    errors: [],
  };

  for (const club of clubs) {
    const validationError = validateClub(club);
    if (validationError) {
      result.errors.push(`${club.sourceId || "unknown"}: ${validationError}`);
      continue;
    }

    let existingClubId: string | null;
    try {
      existingClubId = await findExistingClubId(client, club);
    } catch (error) {
      result.errors.push(`${club.sourceId}: ${(error as Error).message}`);
      continue;
    }

    const writeResult = existingClubId
      ? await client
        .from("clubs")
        .update(mapClubToUpdateRow(club))
        .eq("id", existingClubId)
      : await client.from("clubs").insert([mapClubToInsertRow(club)]);

    if (writeResult.error) {
      result.errors.push(
        `${club.sourceId}: write failed — ${writeResult.error.message}`,
      );
      continue;
    }

    if (existingClubId) {
      result.updated++;
    } else {
      result.inserted++;
    }
  }

  return result;
}

/**
 * TODO: Document handleDiscoverClubsRequest.
 */
export async function handleDiscoverClubsRequest(
  req: Request,
  deps: DiscoverClubsDependencies = {},
): Promise<Response> {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  let serviceRoleKey: string;
  try {
    serviceRoleKey = readServiceRoleKey(deps);
  } catch (e) {
    return jsonResponse(
      { error: `Configuration error: ${(e as Error).message}` },
      500,
    );
  }

  if (!requestHasServiceRoleAuthorization(req, serviceRoleKey)) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const url = new URL(req.url);
  const params: DiscoverParams = {
    city: url.searchParams.get("city") ?? undefined,
    stateRegion: url.searchParams.get("stateRegion") ?? undefined,
    source: url.searchParams.get("source") ?? undefined,
  };

  let client: SupabaseClient;
  try {
    client = deps.createServiceClient
      ? deps.createServiceClient()
      : createDefaultServiceClient();
  } catch (e) {
    return jsonResponse(
      { error: `Configuration error: ${(e as Error).message}` },
      500,
    );
  }

  const adapters = deps.adapters ?? DEFAULT_ADAPTERS;
  if (adapters.length === 0) {
    return jsonResponse({ error: "No source adapters configured" }, 400);
  }

  // Filter adapters if source param specified
  const activeAdapters = params.source
    ? adapters.filter((a) => a.name === params.source)
    : adapters;

  if (activeAdapters.length === 0) {
    return jsonResponse(
      { error: `Unknown source: ${params.source}` },
      400,
    );
  }

  const results: DiscoverResult[] = [];
  for (const adapter of activeAdapters) {
    try {
      const clubs = await adapter.discover(params);
      const pipelineResult = await runPipeline(client, clubs, adapter.name);
      results.push(pipelineResult);
    } catch (e) {
      results.push({
        source: adapter.name,
        found: 0,
        inserted: 0,
        updated: 0,
        errors: [`Adapter error: ${(e as Error).message}`],
      });
    }
  }

  return jsonResponse({ results }, 200);
}

if (import.meta.main) {
  Deno.serve(
    (req: Request): Promise<Response> => handleDiscoverClubsRequest(req),
  );
}
