import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import type { DeleteAccountDependencies } from "./index.ts";
import { handleDeleteAccount } from "./index.ts";
import {
  buildDeleteRequest,
  createDualClientFactory,
  createMockSupabaseClient,
  MOCK_SUPABASE_CONFIG,
} from "./test_support.ts";

const VALID_AUTH_HEADER = "Bearer token";

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
    userClient?: ReturnType<typeof createMockSupabaseClient>;
    adminClient?: ReturnType<typeof createMockSupabaseClient>;
    getAuthUserFn?: DeleteAccountDependencies["getAuthUserFn"];
  } = {},
) {
  const userClient = options.userClient ?? createMockSupabaseClient();
  const adminClient = options.adminClient ?? createMockSupabaseClient();
  const factory = createDualClientFactory(userClient, adminClient);

  return {
    userClient,
    adminClient,
    factory,
    deps: {
      createClientFn: factory.createClientFn,
      loadSupabaseConfigFn: () => MOCK_SUPABASE_CONFIG,
      getAuthUserFn: options.getAuthUserFn,
    },
  };
}

Deno.test("handleDeleteAccount returns 204 for OPTIONS requests", async () => {
  const response = await handleDeleteAccount(
    new Request("http://localhost/delete-my-account", { method: "OPTIONS" }),
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

Deno.test("handleDeleteAccount returns 405 for non-POST requests", async () => {
  const response = await handleDeleteAccount(
    new Request("http://localhost/delete-my-account", { method: "GET" }),
  );

  await assertJsonResponse(response, 405, { error: "Method not allowed" });
});

Deno.test("handleDeleteAccount returns 401 when Authorization header is missing", async () => {
  const response = await handleDeleteAccount(buildDeleteRequest());

  await assertJsonResponse(response, 401, {
    error: "Missing or invalid authorization",
  });
});

Deno.test("handleDeleteAccount returns 401 when Authorization header is not Bearer", async () => {
  const response = await handleDeleteAccount(
    buildDeleteRequest("Basic abc123"),
  );

  await assertJsonResponse(response, 401, {
    error: "Missing or invalid authorization",
  });
});

Deno.test("handleDeleteAccount trims bearer token whitespace before forwarding it", async () => {
  const { factory, deps } = buildAuthenticatedDeps({
    getAuthUserFn: async () => ({
      data: { user: null },
      error: { message: "jwt expired" },
    }),
  });

  const response = await handleDeleteAccount(
    buildDeleteRequest("  bearer   token-value   "),
    deps,
  );

  assertEquals(response.status, 401);
  assertEquals(factory.calls.length, 1);
  assertEquals(factory.calls[0]?.options, {
    global: {
      headers: { Authorization: "Bearer token-value" },
    },
  });
});

Deno.test("handleDeleteAccount returns 500 when required env config is missing", async () => {
  const response = await handleDeleteAccount(
    buildDeleteRequest(VALID_AUTH_HEADER),
    {
      loadSupabaseConfigFn: () => null,
    },
  );

  await assertJsonResponse(response, 500, {
    error: "Function configuration is incomplete",
  });
});

Deno.test("handleDeleteAccount returns 401 when auth.getUser fails", async () => {
  const { factory, deps } = buildAuthenticatedDeps({
    getAuthUserFn: async () => ({
      data: { user: null },
      error: { message: "jwt expired" },
    }),
  });
  const response = await handleDeleteAccount(
    buildDeleteRequest(VALID_AUTH_HEADER),
    deps,
  );

  await assertJsonResponse(response, 401, {
    error: "Invalid or expired token",
  });
  assertEquals(factory.calls.length, 1);
  assertEquals(factory.calls, [{
    supabaseUrl: "https://example.supabase.co",
    supabaseKey: "anon-key",
    options: {
      global: {
        headers: { Authorization: "Bearer token" },
      },
    },
  }]);
});

Deno.test("handleDeleteAccount returns 200 after successful storage cleanup and auth deletion", async () => {
  const { adminClient, factory, deps } = buildAuthenticatedDeps({
    userClient: createMockSupabaseClient({ authUserId: "user-123" }),
    adminClient: createMockSupabaseClient({
      listHandler: (bucket) => ({
        data: [{ name: `${bucket}.jpg`, id: `${bucket}-id` }],
        error: null,
      }),
    }),
  });
  const response = await handleDeleteAccount(
    buildDeleteRequest(VALID_AUTH_HEADER),
    deps,
  );

  await assertJsonResponse(response, 200, { success: true });
  assertEquals(factory.calls, [
    {
      supabaseUrl: "https://example.supabase.co",
      supabaseKey: "anon-key",
      options: {
        global: {
          headers: { Authorization: "Bearer token" },
        },
      },
    },
    {
      supabaseUrl: "https://example.supabase.co",
      supabaseKey: "service-role-key",
      options: undefined,
    },
  ]);
  assertEquals(
    adminClient._removeCalls.map((call) => call.bucket),
    ["avatars", "activity-photos"],
  );
  assertEquals(adminClient._deleteUserCalls, ["user-123"]);
});

Deno.test("handleDeleteAccount returns 500 when auth.admin.deleteUser fails", async () => {
  const { deps } = buildAuthenticatedDeps({
    userClient: createMockSupabaseClient({ authUserId: "user-123" }),
    adminClient: createMockSupabaseClient({
      deleteUserErrorMessage: "delete failed",
    }),
  });
  const response = await handleDeleteAccount(
    buildDeleteRequest(VALID_AUTH_HEADER),
    deps,
  );

  await assertJsonResponse(response, 500, {
    error: "Failed to delete account",
  });
});

Deno.test("handleDeleteAccount returns 500 when storage removal throws", async () => {
  const { deps } = buildAuthenticatedDeps({
    userClient: createMockSupabaseClient({ authUserId: "user-123" }),
    adminClient: createMockSupabaseClient({
      listHandler: () => ({
        data: [{ name: "avatar.jpg", id: "avatar-id" }],
        error: null,
      }),
      removeHandler: () => ({
        data: null,
        error: { message: "storage remove failed" },
      }),
    }),
  });
  const response = await handleDeleteAccount(
    buildDeleteRequest(VALID_AUTH_HEADER),
    deps,
  );

  await assertJsonResponse(response, 500, {
    error: "Internal error during account deletion",
  });
});
