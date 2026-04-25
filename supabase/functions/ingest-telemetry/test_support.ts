/**
 * @module test_support for ingest-telemetry edge function.
 *
 * Provides a single-client mock factory (no service-role / admin client needed)
 * that records auth.getUser() and .from('telemetry_events').upsert() calls for
 * assertion without real network or database access.
 */

import type { IngestSupabaseConfig } from "./index.ts";

export interface UpsertCall {
  table: string;
  rows: Record<string, unknown>[];
  options: { onConflict?: string; ignoreDuplicates?: boolean };
}

export interface MockIngestClientOptions {
  authUserId?: string | null;
  authErrorMessage?: string | null;
  upsertHandler?: (
    table: string,
    rows: Record<string, unknown>[],
    options: { onConflict?: string; ignoreDuplicates?: boolean },
  ) => { data: unknown; error: { message: string } | null };
}

// deno-lint-ignore no-explicit-any
export type MockIngestClient = any;

export function createMockIngestClient(
  options: MockIngestClientOptions = {},
): MockIngestClient {
  const upsertCalls: UpsertCall[] = [];

  return {
    from(table: string) {
      return {
        upsert(
          rows: Record<string, unknown>[],
          upsertOptions: { onConflict?: string; ignoreDuplicates?: boolean } =
            {},
        ) {
          upsertCalls.push({ table, rows: [...rows], options: upsertOptions });
          const result = options.upsertHandler?.(table, rows, upsertOptions) ??
            { data: rows, error: null };
          return Promise.resolve(result);
        },
      };
    },
    auth: {
      getUser() {
        const userId = options.authUserId ?? "user-1";
        return Promise.resolve({
          data: { user: userId ? { id: userId } : null },
          error: options.authErrorMessage
            ? { message: options.authErrorMessage }
            : null,
        });
      },
    },
    _upsertCalls: upsertCalls,
  };
}

export interface SingleClientFactory {
  createClientFn: (
    supabaseUrl: string,
    supabaseKey: string,
    options?: { global?: { headers?: Record<string, string> } },
  ) => MockIngestClient;
  calls: Array<{
    supabaseUrl: string;
    supabaseKey: string;
    options?: { global?: { headers?: Record<string, string> } };
  }>;
}

export function createSingleClientFactory(
  client: MockIngestClient,
): SingleClientFactory {
  const calls: SingleClientFactory["calls"] = [];
  return {
    createClientFn: (supabaseUrl, supabaseKey, options) => {
      calls.push({ supabaseUrl, supabaseKey, options });
      return client;
    },
    calls,
  };
}

export const MOCK_SUPABASE_CONFIG: IngestSupabaseConfig = {
  supabaseUrl: "https://example.supabase.co",
  anonKey: "anon-key",
};

const SUPABASE_ENV_KEYS = [
  "SUPABASE_URL",
  "SUPABASE_ANON_KEY",
] as const;

export async function withEnvVarGuard(
  fn: () => void | Promise<void>,
): Promise<void> {
  const saved = new Map(
    SUPABASE_ENV_KEYS.map((k) => [k, Deno.env.get(k)] as const),
  );
  try {
    await fn();
  } finally {
    for (const [k, v] of saved) {
      if (v === undefined) {
        Deno.env.delete(k);
      } else {
        Deno.env.set(k, v);
      }
    }
  }
}

export function buildIngestRequest(
  method: string,
  authHeader?: string,
  body?: Record<string, unknown>,
): Request {
  const headers = new Headers();
  if (authHeader) {
    headers.set("Authorization", authHeader);
  }
  if (body) {
    headers.set("Content-Type", "application/json");
  }

  return new Request("http://localhost/ingest-telemetry", {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
}
