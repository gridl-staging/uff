import type { StorageObject, SupabaseConfig } from "./index.ts";

export interface MockResponse<T> {
  data: T | null;
  error: { message: string } | null;
}

export interface StorageListCall {
  bucket: string;
  prefix: string;
  limit: number;
  offset: number;
}

export interface StorageRemoveCall {
  bucket: string;
  paths: string[];
}

export interface MockDeleteAccountClientOptions {
  listHandler?: (
    bucket: string,
    prefix: string,
    options: { limit: number; offset: number },
  ) => MockResponse<StorageObject[]>;
  removeHandler?: (
    bucket: string,
    paths: string[],
  ) => MockResponse<unknown>;
  authUserId?: string | null;
  authErrorMessage?: string | null;
  deleteUserErrorMessage?: string | null;
}

export interface MockDeleteAccountClient {
  storage: {
    from: (bucket: string) => {
      list: (
        prefix: string,
        options: { limit: number; offset: number },
      ) => Promise<MockResponse<StorageObject[]>>;
      remove: (paths: string[]) => Promise<MockResponse<unknown>>;
    };
  };
  auth: {
    getUser: () => Promise<{
      data: { user: { id: string } | null };
      error: { message: string } | null;
    }>;
    admin: {
      deleteUser: (userId: string) => Promise<MockResponse<unknown>>;
    };
  };
  _listCalls: StorageListCall[];
  _removeCalls: StorageRemoveCall[];
  _deleteUserCalls: string[];
}

function resolveMockResponse<T>(
  response: MockResponse<T>,
): Promise<MockResponse<T>> {
  return Promise.resolve(response);
}

function maybeError(
  message: string | null | undefined,
): { message: string } | null {
  return message ? { message } : null;
}

function restoreEnvVar(key: string, value: string | undefined): void {
  if (value === undefined) {
    Deno.env.delete(key);
    return;
  }

  Deno.env.set(key, value);
}

export function createMockSupabaseClient(
  options: MockDeleteAccountClientOptions = {},
): MockDeleteAccountClient {
  const listCalls: StorageListCall[] = [];
  const removeCalls: StorageRemoveCall[] = [];
  const deleteUserCalls: string[] = [];

  return {
    storage: {
      from(bucket: string) {
        return {
          list(
            prefix: string,
            listOptions: { limit: number; offset: number },
          ): Promise<MockResponse<StorageObject[]>> {
            listCalls.push({
              bucket,
              prefix,
              limit: listOptions.limit,
              offset: listOptions.offset,
            });
            const result = options.listHandler?.(bucket, prefix, {
              limit: listOptions.limit,
              offset: listOptions.offset,
            }) ?? { data: [], error: null };
            return resolveMockResponse(result);
          },
          remove(paths: string[]): Promise<MockResponse<unknown>> {
            removeCalls.push({ bucket, paths: [...paths] });
            const result = options.removeHandler?.(bucket, paths) ?? {
              data: null,
              error: null,
            };
            return resolveMockResponse(result);
          },
        };
      },
    },
    auth: {
      getUser() {
        const userId = options.authUserId ?? "user-1";
        return Promise.resolve({
          data: { user: userId ? { id: userId } : null },
          error: maybeError(options.authErrorMessage),
        });
      },
      admin: {
        deleteUser(userId: string): Promise<MockResponse<unknown>> {
          deleteUserCalls.push(userId);
          return resolveMockResponse({
            data: null,
            error: maybeError(options.deleteUserErrorMessage),
          });
        },
      },
    },
    _listCalls: listCalls,
    _removeCalls: removeCalls,
    _deleteUserCalls: deleteUserCalls,
  };
}

const SUPABASE_ENV_KEYS = [
  "SUPABASE_URL",
  "SUPABASE_SERVICE_ROLE_KEY",
  "SUPABASE_ANON_KEY",
] as const;

// Saves all Supabase env vars, runs the callback, then restores originals.
// Prevents env-var pollution between tests.
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
      restoreEnvVar(k, v);
    }
  }
}

export const MOCK_SUPABASE_CONFIG: SupabaseConfig = {
  supabaseUrl: "https://example.supabase.co",
  serviceRoleKey: "service-role-key",
  anonKey: "anon-key",
};

export interface DualClientFactory {
  createClientFn: (
    supabaseUrl: string,
    supabaseKey: string,
    options?: { global?: { headers?: Record<string, string> } },
  ) => MockDeleteAccountClient;
  calls: Array<{
    supabaseUrl: string;
    supabaseKey: string;
    options?: { global?: { headers?: Record<string, string> } };
  }>;
}

// Returns the first client on call 1 (user client) and the second on call 2+
// (admin client), tracking all call arguments for assertions.
export function createDualClientFactory(
  userClient: MockDeleteAccountClient,
  adminClient: MockDeleteAccountClient,
): DualClientFactory {
  let callCount = 0;
  const calls: DualClientFactory["calls"] = [];
  return {
    createClientFn: (supabaseUrl, supabaseKey, options) => {
      callCount += 1;
      calls.push({ supabaseUrl, supabaseKey, options });
      return callCount === 1 ? userClient : adminClient;
    },
    calls,
  };
}

export function buildDeleteRequest(authHeader?: string): Request {
  const headers = new Headers();
  if (authHeader) {
    headers.set("Authorization", authHeader);
  }

  return new Request("http://localhost/delete-my-account", {
    method: "POST",
    headers,
  });
}
