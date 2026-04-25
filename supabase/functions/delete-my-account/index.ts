/**
 * @module delete-my-account edge function.
 */
// Stage 7: Self-service account deletion Edge Function
//
// Authenticates the caller from their JWT, removes their storage objects
// via the Storage API, then deletes their auth.users row so FK cascades
// clean up all relational data (profiles, activities, track_points, etc.).
//
// Runs with service-role credentials to perform admin operations.
// Does NOT accept a target user_id - identity is derived from the JWT.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface StorageObject {
  name: string;
  id?: string | null;
}

export interface SupabaseConfig {
  supabaseUrl: string;
  serviceRoleKey: string;
  anonKey: string;
}

// deno-lint-ignore no-explicit-any
export type SupabaseClient = any;

export const STORAGE_BATCH_SIZE = 100;
export const USER_STORAGE_BUCKETS = ["avatars", "activity-photos"] as const;
export const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, apikey",
};

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

export interface DeleteAccountDependencies {
  createClientFn?: CreateClientFn;
  loadSupabaseConfigFn?: () => SupabaseConfig | null;
  getAuthUserFn?: GetAuthUserFn;
}

export function jsonResponse(
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

export function loadSupabaseConfig(): SupabaseConfig | null {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!supabaseUrl || !serviceRoleKey || !anonKey) {
    return null;
  }

  return { supabaseUrl, serviceRoleKey, anonKey };
}

/**
 * TODO: Document normalizeBearerAuthorizationHeader.
 */
export function normalizeBearerAuthorizationHeader(
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
 * TODO: Document listStorageEntries.
 */
export async function listStorageEntries(
  adminClient: SupabaseClient,
  bucket: string,
  prefix: string,
): Promise<StorageObject[]> {
  const entries: StorageObject[] = [];
  let offset = 0;

  while (true) {
    const { data, error } = await adminClient.storage.from(bucket).list(
      prefix,
      {
        limit: STORAGE_BATCH_SIZE,
        offset,
        sortBy: { column: "name", order: "asc" },
      },
    );

    if (error) {
      throw new Error(`Failed to list ${bucket}/${prefix}: ${error.message}`);
    }

    const batch = (data ?? []) as StorageObject[];
    entries.push(...batch);
    if (batch.length < STORAGE_BATCH_SIZE) {
      return entries;
    }
    offset += batch.length;
  }
}

/**
 * TODO: Document collectStoragePaths.
 */
export async function collectStoragePaths(
  adminClient: SupabaseClient,
  bucket: string,
  userId: string,
): Promise<string[]> {
  const pendingPrefixes = [userId];
  const paths: string[] = [];

  while (pendingPrefixes.length > 0) {
    const prefix = pendingPrefixes.pop()!;
    const entries = await listStorageEntries(adminClient, bucket, prefix);

    for (const entry of entries) {
      const path = `${prefix}/${entry.name}`;
      if (entry.id) {
        paths.push(path);
      } else {
        pendingPrefixes.push(path);
      }
    }
  }

  return paths;
}

export async function removeStorageObjects(
  adminClient: SupabaseClient,
  bucket: string,
  userId: string,
): Promise<void> {
  const paths = await collectStoragePaths(adminClient, bucket, userId);
  for (let index = 0; index < paths.length; index += STORAGE_BATCH_SIZE) {
    const batch = paths.slice(index, index + STORAGE_BATCH_SIZE);
    const { error } = await adminClient.storage.from(bucket).remove(batch);
    if (error) {
      throw new Error(`Failed to remove ${bucket} objects: ${error.message}`);
    }
  }
}

export async function removeUserStorage(
  adminClient: SupabaseClient,
  userId: string,
): Promise<void> {
  for (const bucket of USER_STORAGE_BUCKETS) {
    await removeStorageObjects(adminClient, bucket, userId);
  }
}

/**
 * TODO: Document handleDeleteAccount.
 */
export async function handleDeleteAccount(
  req: Request,
  deps: DeleteAccountDependencies = {},
): Promise<Response> {
  const {
    createClientFn = createClient as CreateClientFn,
    loadSupabaseConfigFn = loadSupabaseConfig,
    getAuthUserFn = (userClient: SupabaseClient) => userClient.auth.getUser(),
  } = deps;

  // Handle CORS preflight
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

  const supabaseConfig = loadSupabaseConfigFn();
  if (!supabaseConfig) {
    return jsonResponse({ error: "Function configuration is incomplete" }, 500);
  }
  const { supabaseUrl, serviceRoleKey, anonKey } = supabaseConfig;

  // Verify caller identity from their JWT
  const userClient = createClientFn(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error: authError,
  } = await getAuthUserFn(userClient);

  if (authError || !user) {
    return jsonResponse({ error: "Invalid or expired token" }, 401);
  }

  const userId = user.id;
  const adminClient = createClientFn(supabaseUrl, serviceRoleKey);

  try {
    await removeUserStorage(adminClient, userId);

    // Delete the auth user - FK cascades handle relational cleanup
    const { error: deleteError } = await adminClient.auth.admin.deleteUser(
      userId,
    );

    if (deleteError) {
      return jsonResponse({ error: "Failed to delete account" }, 500);
    }

    return jsonResponse({ success: true }, 200);
  } catch {
    return jsonResponse(
      { error: "Internal error during account deletion" },
      500,
    );
  }
}

if (import.meta.main) {
  Deno.serve((req: Request): Promise<Response> => handleDeleteAccount(req));
}
