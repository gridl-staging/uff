// Tests for the send-notification delivery path. Routing/lookup coverage lives
// in index_test.ts; this file keeps delivery assertions separate so the Stage 6
// backend test suite stays under the hard file-size limit.

import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  handleFcmResponse,
  handleNotificationRequest,
  sendFcmMessage,
  shouldSkipNotification,
} from "./index.ts";
import { createMockClient, makePayload, makeTestConfig } from "./test_support.ts";

const testWebhookSecret = "webhook-secret";

function buildWebhookRequest(payload: ReturnType<typeof makePayload>): Request {
  return new Request("http://localhost/send-notification", {
    method: "POST",
    headers: {
      "x-webhook-secret": testWebhookSecret,
    },
    body: JSON.stringify(payload),
  });
}

Deno.test("sendFcmMessage — builds correct FCM HTTP v1 request body", async () => {
  let capturedUrl = "";
  let capturedBody = "";
  let capturedHeaders: Record<string, string> = {};

  const mockFetch = (
    url: string | URL | Request,
    init?: RequestInit,
  ): Promise<Response> => {
    capturedUrl = url as string;
    capturedBody = init?.body as string;
    const headers = new Headers(init?.headers);
    capturedHeaders = {
      "authorization": headers.get("authorization") ?? "",
      "content-type": headers.get("content-type") ?? "",
    };
    return Promise.resolve(
      new Response(JSON.stringify({ name: "msg-123" }), { status: 200 }),
    );
  };

  await sendFcmMessage(
    {
      projectId: "my-project",
      accessToken: "test-token",
      recipientToken: "device-token",
      title: "New Like",
      body: "Alice liked your activity",
    },
    mockFetch,
  );

  assertEquals(
    capturedUrl,
    "https://fcm.googleapis.com/v1/projects/my-project/messages:send",
  );
  assertEquals(capturedHeaders["authorization"], "Bearer test-token");
  assertEquals(capturedHeaders["content-type"], "application/json");

  const parsed = JSON.parse(capturedBody);
  assertEquals(parsed.message.token, "device-token");
  assertEquals(parsed.message.notification.title, "New Like");
  assertEquals(parsed.message.notification.body, "Alice liked your activity");
});

Deno.test("shouldSkipNotification — actor equals recipient returns true", () => {
  assertEquals(shouldSkipNotification("user-1", "user-1"), true);
});

Deno.test("shouldSkipNotification — actor differs from recipient returns false", () => {
  assertEquals(shouldSkipNotification("user-1", "user-2"), false);
});

Deno.test("handleFcmResponse — 200 OK does not clear token", async () => {
  const client = createMockClient({});
  const response = new Response(
    JSON.stringify({ name: "msg-id" }),
    { status: 200 },
  );
  const result = await handleFcmResponse(
    client,
    "user-1",
    "token-1",
    response,
  );
  assertEquals(result.tokenCleared, false);
  assertEquals(result.cleanupError, null);
  assertEquals(client._updateCalls.length, 0);
});

Deno.test("handleFcmResponse — UNREGISTERED error clears fcm_token", async () => {
  const client = createMockClient({});
  const errorBody = {
    error: {
      code: 404,
      message: "Requested entity was not found.",
      status: "NOT_FOUND",
      details: [
        {
          "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
          errorCode: "UNREGISTERED",
        },
      ],
    },
  };
  const response = new Response(JSON.stringify(errorBody), { status: 404 });
  const result = await handleFcmResponse(
    client,
    "user-1",
    "token-1",
    response,
  );

  assertEquals(result.tokenCleared, true);
  assertEquals(result.cleanupError, null);
  assertEquals(client._updateCalls.length, 1);
  assertEquals(client._updateCalls[0].table, "profiles");
  assertEquals(client._updateCalls[0].data, { fcm_token: null });
  assertEquals(client._updateCalls[0].filters, [
    { col: "id", val: "user-1" },
    { col: "fcm_token", val: "token-1" },
  ]);
});

Deno.test("handleFcmResponse — INVALID_ARGUMENT error clears fcm_token", async () => {
  const client = createMockClient({});
  const errorBody = {
    error: {
      code: 400,
      message: "The registration token is not a valid FCM registration token",
      status: "INVALID_ARGUMENT",
      details: [
        {
          "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
          errorCode: "INVALID_ARGUMENT",
        },
      ],
    },
  };
  const response = new Response(JSON.stringify(errorBody), { status: 400 });
  const result = await handleFcmResponse(
    client,
    "user-1",
    "token-2",
    response,
  );

  assertEquals(result.tokenCleared, true);
  assertEquals(result.cleanupError, null);
  assertEquals(client._updateCalls.length, 1);
});

Deno.test("handleFcmResponse — 500 server error does not clear token", async () => {
  const client = createMockClient({});
  const errorBody = {
    error: {
      code: 500,
      message: "Internal error",
      status: "INTERNAL",
      details: [
        {
          "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
          errorCode: "INTERNAL",
        },
      ],
    },
  };
  const response = new Response(JSON.stringify(errorBody), { status: 500 });
  const result = await handleFcmResponse(
    client,
    "user-1",
    "token-3",
    response,
  );

  assertEquals(result.tokenCleared, false);
  assertEquals(result.cleanupError, null);
  assertEquals(client._updateCalls.length, 0);
});

Deno.test("handleFcmResponse — unparseable response body does not clear token", async () => {
  const client = createMockClient({});
  const response = new Response("not json", { status: 502 });
  const result = await handleFcmResponse(
    client,
    "user-1",
    "token-4",
    response,
  );

  assertEquals(result.tokenCleared, false);
  assertEquals(result.cleanupError, null);
  assertEquals(client._updateCalls.length, 0);
});

Deno.test("handleFcmResponse — stale-token cleanup only succeeds when the rejected token still matches", async () => {
  const client = createMockClient({
    "profiles:update:id=user-1&fcm_token=stale-token": {
      data: null,
      error: null,
    },
  });
  const errorBody = {
    error: {
      code: 404,
      message: "Requested entity was not found.",
      status: "NOT_FOUND",
      details: [
        {
          "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
          errorCode: "UNREGISTERED",
        },
      ],
    },
  };
  const response = new Response(JSON.stringify(errorBody), { status: 404 });
  const result = await handleFcmResponse(
    client,
    "user-1",
    "stale-token",
    response,
  );

  assertEquals(result.tokenCleared, false);
  assertEquals(result.cleanupError, null);
  assertEquals(client._updateCalls.length, 1);
  assertEquals(client._updateCalls[0].filters, [
    { col: "id", val: "user-1" },
    { col: "fcm_token", val: "stale-token" },
  ]);
});

Deno.test("handleFcmResponse — stale-token cleanup query error is surfaced for retry", async () => {
  const client = createMockClient({
    "profiles:update:id=user-1&fcm_token=token-5": {
      data: null,
      error: { message: "write failed" },
    },
  });
  const errorBody = {
    error: {
      code: 404,
      message: "Requested entity was not found.",
      status: "NOT_FOUND",
      details: [
        {
          "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
          errorCode: "UNREGISTERED",
        },
      ],
    },
  };
  const response = new Response(JSON.stringify(errorBody), { status: 404 });
  const result = await handleFcmResponse(
    client,
    "user-1",
    "token-5",
    response,
  );

  assertEquals(result.tokenCleared, false);
  assertEquals(
    result.cleanupError,
    "profiles stale-token cleanup failed: write failed",
  );
});

Deno.test("handleNotificationRequest — transient FCM failure returns non-2xx (502) for webhook retry", async () => {
  let sentProjectId: string | null = null;
  let sentRecipientToken: string | null = null;
  let handleResponseCallCount = 0;

  const request = buildWebhookRequest(
    makePayload({
      type: "INSERT",
      table: "kudos",
      record: { activity_id: "act-1", user_id: "actor-1" },
    }),
  );

  const response = await handleNotificationRequest(request, {
    createClientFn: () => createMockClient({}),
    loadNotificationConfigFn: () => makeTestConfig(testWebhookSecret),
    buildNotificationJobFn: () => ({
      eventType: "kudos",
      actorId: "actor-1",
      activityId: "act-1",
    }),
    loadNotificationTargetFn: async () => ({
      target: {
        recipientId: "owner-1",
        recipientToken: "token-1",
        actorDisplayName: "Alice",
      },
      error: null,
    }),
    shouldSkipNotificationFn: () => false,
    mintFcmAccessTokenFn: async () => "access-token",
    sendFcmMessageFn: async (params) => {
      sentProjectId = params.projectId;
      sentRecipientToken = params.recipientToken;
      return new Response(JSON.stringify({ error: { status: "INTERNAL" } }), {
        status: 503,
      });
    },
    handleFcmResponseFn: async () => {
      handleResponseCallCount += 1;
      return { tokenCleared: false, cleanupError: null };
    },
  });

  assertEquals(response.status, 502);
  const body = await response.json();
  assertEquals(body.sent, false);
  assertEquals(body.tokenCleared, false);
  assertEquals(body.fcmStatus, 503);
  assertEquals(sentProjectId, "project-id");
  assertEquals(sentRecipientToken, "token-1");
  assertEquals(handleResponseCallCount, 1);
});

Deno.test("handleNotificationRequest — stale token cleanup returns 200 to avoid pointless retry", async () => {
  let sendCallCount = 0;
  let handleResponseCallCount = 0;

  const request = buildWebhookRequest(
    makePayload({
      type: "INSERT",
      table: "kudos",
      record: { activity_id: "act-2", user_id: "actor-2" },
    }),
  );

  const response = await handleNotificationRequest(request, {
    createClientFn: () => createMockClient({}),
    loadNotificationConfigFn: () => makeTestConfig(testWebhookSecret),
    buildNotificationJobFn: () => ({
      eventType: "kudos",
      actorId: "actor-2",
      activityId: "act-2",
    }),
    loadNotificationTargetFn: async () => ({
      target: {
        recipientId: "owner-2",
        recipientToken: "token-2",
        actorDisplayName: "Bob",
      },
      error: null,
    }),
    shouldSkipNotificationFn: () => false,
    mintFcmAccessTokenFn: async () => "access-token",
    sendFcmMessageFn: async () => {
      sendCallCount += 1;
      return new Response(JSON.stringify({ error: { status: "NOT_FOUND" } }), {
        status: 404,
      });
    },
    handleFcmResponseFn: async () => {
      handleResponseCallCount += 1;
      return { tokenCleared: true, cleanupError: null };
    },
  });

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.sent, false);
  assertEquals(body.tokenCleared, true);
  assertEquals(body.fcmStatus, 404);
  assertEquals(sendCallCount, 1);
  assertEquals(handleResponseCallCount, 1);
});

Deno.test("handleNotificationRequest — stale-token cleanup error returns 500 so the webhook is not falsely acknowledged", async () => {
  const request = buildWebhookRequest(
    makePayload({
      type: "INSERT",
      table: "comments",
      record: { activity_id: "act-3", user_id: "actor-3" },
    }),
  );

  const response = await handleNotificationRequest(request, {
    createClientFn: () => createMockClient({}),
    loadNotificationConfigFn: () => makeTestConfig(testWebhookSecret),
    buildNotificationJobFn: () => ({
      eventType: "comment",
      actorId: "actor-3",
      activityId: "act-3",
    }),
    loadNotificationTargetFn: async () => ({
      target: {
        recipientId: "owner-3",
        recipientToken: "token-3",
        actorDisplayName: "Casey",
      },
      error: null,
    }),
    shouldSkipNotificationFn: () => false,
    mintFcmAccessTokenFn: async () => "access-token",
    sendFcmMessageFn: async () =>
      new Response(JSON.stringify({ error: { status: "NOT_FOUND" } }), {
        status: 404,
      }),
    handleFcmResponseFn: async () => ({
      tokenCleared: false,
      cleanupError: "profiles stale-token cleanup failed: write failed",
    }),
  });

  assertEquals(response.status, 500);
  const body = await response.json();
  assertEquals(body.error, "Stale token cleanup failed");
});

Deno.test("handleNotificationRequest — missing webhook secret returns 401 before privileged work", async () => {
  let createClientCalled = false;

  const request = new Request("http://localhost/send-notification", {
    method: "POST",
    body: JSON.stringify(makePayload({
      type: "INSERT",
      table: "kudos",
      record: { activity_id: "act-4", user_id: "actor-4" },
    })),
  });

  const response = await handleNotificationRequest(request, {
    createClientFn: () => {
      createClientCalled = true;
      return createMockClient({});
    },
    loadNotificationConfigFn: () => makeTestConfig(testWebhookSecret),
  });

  assertEquals(response.status, 401);
  assertEquals(createClientCalled, false);
  const body = await response.json();
  assertEquals(body.error, "Unauthorized webhook request");
});

// ===========================================================================
// handleNotificationRequest — integration coverage for remaining code paths
// ===========================================================================

Deno.test("handleNotificationRequest — successful FCM delivery returns 200 with sent=true", async () => {
  const request = buildWebhookRequest(
    makePayload({
      type: "INSERT",
      table: "kudos",
      record: { activity_id: "act-5", user_id: "actor-5" },
    }),
  );

  const response = await handleNotificationRequest(request, {
    createClientFn: () => createMockClient({}),
    loadNotificationConfigFn: () => makeTestConfig(testWebhookSecret),
    buildNotificationJobFn: () => ({
      eventType: "kudos",
      actorId: "actor-5",
      activityId: "act-5",
    }),
    loadNotificationTargetFn: async () => ({
      target: {
        recipientId: "owner-5",
        recipientToken: "token-5",
        actorDisplayName: "Eve",
      },
      error: null,
    }),
    shouldSkipNotificationFn: () => false,
    mintFcmAccessTokenFn: async () => "access-token",
    sendFcmMessageFn: async () =>
      new Response(JSON.stringify({ name: "msg-ok" }), { status: 200 }),
    handleFcmResponseFn: async () => ({
      tokenCleared: false,
      cleanupError: null,
    }),
  });

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.sent, true);
});

Deno.test("handleNotificationRequest — self-notification is suppressed with skipped response", async () => {
  const request = buildWebhookRequest(
    makePayload({
      type: "INSERT",
      table: "kudos",
      record: { activity_id: "act-6", user_id: "self-user" },
    }),
  );

  let sendCalled = false;
  const response = await handleNotificationRequest(request, {
    createClientFn: () => createMockClient({}),
    loadNotificationConfigFn: () => makeTestConfig(testWebhookSecret),
    buildNotificationJobFn: () => ({
      eventType: "kudos",
      actorId: "self-user",
      activityId: "act-6",
    }),
    loadNotificationTargetFn: async () => ({
      target: {
        recipientId: "self-user",
        recipientToken: "token-self",
        actorDisplayName: "Self",
      },
      error: null,
    }),
    shouldSkipNotificationFn: (actorId, recipientId) =>
      actorId === recipientId,
    sendFcmMessageFn: async () => {
      sendCalled = true;
      return new Response("{}", { status: 200 });
    },
  });

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.skipped, true);
  assertEquals(body.reason, "self_notification");
  assertEquals(sendCalled, false);
});

Deno.test("handleNotificationRequest — CORS preflight returns 204 with no body", async () => {
  const request = new Request("http://localhost/send-notification", {
    method: "OPTIONS",
  });

  const response = await handleNotificationRequest(request, {});
  assertEquals(response.status, 204);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), "*");
  assertEquals(response.headers.get("Access-Control-Allow-Methods"), "POST, OPTIONS");
});

Deno.test("handleNotificationRequest — non-POST method returns 405", async () => {
  const request = new Request("http://localhost/send-notification", {
    method: "GET",
  });

  const response = await handleNotificationRequest(request, {
    loadNotificationConfigFn: () => makeTestConfig(testWebhookSecret),
  });

  assertEquals(response.status, 405);
  const body = await response.json();
  assertEquals(body.error, "Method not allowed");
});

Deno.test("handleNotificationRequest — no recipient token returns 200 skipped", async () => {
  const request = buildWebhookRequest(
    makePayload({
      type: "INSERT",
      table: "comments",
      record: { activity_id: "act-7", user_id: "actor-7" },
    }),
  );

  const response = await handleNotificationRequest(request, {
    createClientFn: () => createMockClient({}),
    loadNotificationConfigFn: () => makeTestConfig(testWebhookSecret),
    buildNotificationJobFn: () => ({
      eventType: "comment",
      actorId: "actor-7",
      activityId: "act-7",
    }),
    loadNotificationTargetFn: async () => ({
      target: null,
      error: null,
    }),
  });

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.skipped, true);
  assertEquals(body.reason, "no_recipient_token");
});

// ===========================================================================
// handleNotificationRequest — remaining handler branches (bug fix:
// notification-handler-coverage-overstated)
// ===========================================================================

Deno.test("handleNotificationRequest — incomplete config returns 500 before any DB work", async () => {
  let createClientCalled = false;

  const request = buildWebhookRequest(
    makePayload({
      type: "INSERT",
      table: "kudos",
      record: { activity_id: "act-cfg", user_id: "actor-cfg" },
    }),
  );

  const response = await handleNotificationRequest(request, {
    createClientFn: () => {
      createClientCalled = true;
      return createMockClient({});
    },
    loadNotificationConfigFn: () => null,
  });

  assertEquals(response.status, 500);
  const body = await response.json();
  assertEquals(body.error, "Function configuration is incomplete");
  assertEquals(createClientCalled, false);
});

Deno.test("handleNotificationRequest — invalid JSON payload returns 400", async () => {
  const request = new Request("http://localhost/send-notification", {
    method: "POST",
    headers: {
      "x-webhook-secret": testWebhookSecret,
    },
    body: "not valid json {{{",
  });

  const response = await handleNotificationRequest(request, {
    loadNotificationConfigFn: () => makeTestConfig(testWebhookSecret),
  });

  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error, "Invalid JSON payload");
});

Deno.test("handleNotificationRequest — unsupported event returns 200 skipped with unsupported_event reason", async () => {
  const request = buildWebhookRequest(
    makePayload({
      type: "DELETE",
      table: "kudos",
      record: { activity_id: "act-del", user_id: "actor-del" },
    }),
  );

  let createClientCalled = false;
  const response = await handleNotificationRequest(request, {
    createClientFn: () => {
      createClientCalled = true;
      return createMockClient({});
    },
    loadNotificationConfigFn: () => makeTestConfig(testWebhookSecret),
  });

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.skipped, true);
  assertEquals(body.reason, "unsupported_event");
  assertEquals(createClientCalled, false);
});

Deno.test("handleNotificationRequest — recipient lookup failure returns 500 for webhook retry", async () => {
  const request = buildWebhookRequest(
    makePayload({
      type: "INSERT",
      table: "kudos",
      record: { activity_id: "act-err", user_id: "actor-err" },
    }),
  );

  const response = await handleNotificationRequest(request, {
    createClientFn: () => createMockClient({}),
    loadNotificationConfigFn: () => makeTestConfig(testWebhookSecret),
    buildNotificationJobFn: () => ({
      eventType: "kudos",
      actorId: "actor-err",
      activityId: "act-err",
    }),
    loadNotificationTargetFn: async () => ({
      target: null,
      error: "activities lookup failed: connection refused",
    }),
  });

  assertEquals(response.status, 500);
  const body = await response.json();
  assertEquals(body.error, "Recipient lookup failed");
  assertEquals(body.detail, "activities lookup failed: connection refused");
});

Deno.test("handleNotificationRequest — delivery exception (mintFcmAccessToken throws) returns 500", async () => {
  const request = buildWebhookRequest(
    makePayload({
      type: "INSERT",
      table: "kudos",
      record: { activity_id: "act-throw", user_id: "actor-throw" },
    }),
  );

  const response = await handleNotificationRequest(request, {
    createClientFn: () => createMockClient({}),
    loadNotificationConfigFn: () => makeTestConfig(testWebhookSecret),
    buildNotificationJobFn: () => ({
      eventType: "kudos",
      actorId: "actor-throw",
      activityId: "act-throw",
    }),
    loadNotificationTargetFn: async () => ({
      target: {
        recipientId: "owner-throw",
        recipientToken: "token-throw",
        actorDisplayName: "Thrower",
      },
      error: null,
    }),
    shouldSkipNotificationFn: () => false,
    mintFcmAccessTokenFn: async () => {
      throw new Error("PEM import failed: invalid key format");
    },
  });

  assertEquals(response.status, 500);
  const body = await response.json();
  assertEquals(body.error, "FCM delivery failed");
  assertEquals(body.detail, "PEM import failed: invalid key format");
});
