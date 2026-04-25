// Tests for send-notification Edge Function
//
// Covers: webhook routing (buildNotificationJob) and recipient lookup
// (loadNotificationTarget). Delivery-path coverage lives in
// index_delivery_test.ts so each backend test file stays below the hard size
// limit while keeping the Stage 6 seam fully exercised.

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  buildNotificationJob,
  loadNotificationConfig,
  loadNotificationTarget,
} from "./index.ts";
import { createMockClient, makePayload } from "./test_support.ts";

// ===========================================================================
// Parent 1: buildNotificationJob — pure webhook routing
// ===========================================================================

Deno.test("buildNotificationJob — kudos INSERT returns activity notification job", () => {
  const payload = makePayload({
    type: "INSERT",
    table: "kudos",
    record: { activity_id: "act-1", user_id: "actor-1" },
  });
  const job = buildNotificationJob(payload);
  assertExists(job);
  assertEquals(job.eventType, "kudos");
  assertEquals(job.actorId, "actor-1");
  assertEquals((job as { activityId: string }).activityId, "act-1");
});

Deno.test("buildNotificationJob — comments INSERT returns activity notification job", () => {
  const payload = makePayload({
    type: "INSERT",
    table: "comments",
    record: { activity_id: "act-2", user_id: "actor-2" },
  });
  const job = buildNotificationJob(payload);
  assertExists(job);
  assertEquals(job.eventType, "comment");
  assertEquals(job.actorId, "actor-2");
  assertEquals((job as { activityId: string }).activityId, "act-2");
});

Deno.test("buildNotificationJob — follows UPDATE pending→accepted returns follow job with follower_id as recipient", () => {
  const payload = makePayload({
    type: "UPDATE",
    table: "follows",
    record: {
      follower_id: "requester-1",
      following_id: "accepter-1",
      status: "accepted",
    },
    old_record: {
      follower_id: "requester-1",
      following_id: "accepter-1",
      status: "pending",
    },
  });
  const job = buildNotificationJob(payload);
  assertExists(job);
  assertEquals(job.eventType, "follow_accepted");
  assertEquals(job.actorId, "accepter-1");
  assertEquals((job as { recipientId: string }).recipientId, "requester-1");
});

Deno.test("buildNotificationJob — follows UPDATE accepted→accepted returns null", () => {
  const payload = makePayload({
    type: "UPDATE",
    table: "follows",
    record: { status: "accepted" },
    old_record: { status: "accepted" },
  });
  assertEquals(buildNotificationJob(payload), null);
});

Deno.test("buildNotificationJob — follows UPDATE pending→pending returns null", () => {
  const payload = makePayload({
    type: "UPDATE",
    table: "follows",
    record: { status: "pending" },
    old_record: { status: "pending" },
  });
  assertEquals(buildNotificationJob(payload), null);
});

Deno.test("buildNotificationJob — follows INSERT returns null (unsupported operation)", () => {
  const payload = makePayload({
    type: "INSERT",
    table: "follows",
    record: { follower_id: "a", following_id: "b", status: "pending" },
  });
  assertEquals(buildNotificationJob(payload), null);
});

Deno.test("buildNotificationJob — unsupported table returns null", () => {
  const payload = makePayload({
    type: "INSERT",
    table: "activities",
    record: { id: "act-1" },
  });
  assertEquals(buildNotificationJob(payload), null);
});

Deno.test("buildNotificationJob — kudos DELETE returns null", () => {
  const payload = makePayload({
    type: "DELETE",
    table: "kudos",
    record: { activity_id: "act-1", user_id: "actor-1" },
  });
  assertEquals(buildNotificationJob(payload), null);
});

Deno.test("buildNotificationJob — comments UPDATE returns null", () => {
  const payload = makePayload({
    type: "UPDATE",
    table: "comments",
    record: { activity_id: "act-1", user_id: "actor-1" },
  });
  assertEquals(buildNotificationJob(payload), null);
});

Deno.test("buildNotificationJob — missing activity_id on kudos returns null", () => {
  const payload = makePayload({
    type: "INSERT",
    table: "kudos",
    record: { user_id: "actor-1" },
  });
  assertEquals(buildNotificationJob(payload), null);
});

Deno.test("buildNotificationJob — missing user_id on comments returns null", () => {
  const payload = makePayload({
    type: "INSERT",
    table: "comments",
    record: { activity_id: "act-1" },
  });
  assertEquals(buildNotificationJob(payload), null);
});

Deno.test("loadNotificationConfig — normalizes escaped newlines in FCM private key", () => {
  const originalValues = new Map<string, string | undefined>();
  const envEntries = [
    ["SUPABASE_URL", "https://example.supabase.co"],
    ["SUPABASE_SERVICE_ROLE_KEY", "service-role-key"],
    ["NOTIFICATION_WEBHOOK_SECRET", "webhook-secret"],
    ["FCM_PROJECT_ID", "fcm-project-id"],
    ["FCM_CLIENT_EMAIL", "firebase@example.com"],
    [
      "FCM_PRIVATE_KEY",
      "-----BEGIN PRIVATE KEY-----\\nline-one\\nline-two\\n-----END PRIVATE KEY-----",
    ],
  ] as const;

  for (const [key, value] of envEntries) {
    originalValues.set(key, Deno.env.get(key));
    Deno.env.set(key, value);
  }

  try {
    const config = loadNotificationConfig();
    assertExists(config);
    assertEquals(
      config.fcmPrivateKey,
      "-----BEGIN PRIVATE KEY-----\nline-one\nline-two\n-----END PRIVATE KEY-----",
    );
  } finally {
    for (const [key] of envEntries) {
      const originalValue = originalValues.get(key);
      if (originalValue == null) {
        Deno.env.delete(key);
      } else {
        Deno.env.set(key, originalValue);
      }
    }
  }
});

// ===========================================================================
// Parent 2: loadNotificationTarget + sendFcmMessage
// ===========================================================================

Deno.test("loadNotificationTarget — kudos event resolves recipient via activities.user_id", async () => {
  const client = createMockClient({
    "activities:id=act-1": {
      data: { user_id: "owner-1" },
      error: null,
    },
    "profiles:id=owner-1": {
      data: { fcm_token: "fcm-token-1", display_name: "Alice" },
      error: null,
    },
    "profiles:id=actor-1": {
      data: { display_name: "Bob" },
      error: null,
    },
  });

  const job = {
    eventType: "kudos" as const,
    actorId: "actor-1",
    activityId: "act-1",
  };
  const result = await loadNotificationTarget(client, job);

  assertEquals(result.error, null);
  assertExists(result.target);
  assertEquals(result.target.recipientId, "owner-1");
  assertEquals(result.target.recipientToken, "fcm-token-1");
  // actorDisplayName comes from the actor (actor-1 → Bob), not the recipient
  assertEquals(result.target.actorDisplayName, "Bob");
});

Deno.test("loadNotificationTarget — comment event resolves recipient via activities.user_id", async () => {
  const client = createMockClient({
    "activities:id=act-2": {
      data: { user_id: "owner-2" },
      error: null,
    },
    "profiles:id=owner-2": {
      data: { fcm_token: "fcm-token-2", display_name: "Charlie" },
      error: null,
    },
    "profiles:id=actor-2": {
      data: { display_name: "Dana" },
      error: null,
    },
  });

  const job = {
    eventType: "comment" as const,
    actorId: "actor-2",
    activityId: "act-2",
  };
  const result = await loadNotificationTarget(client, job);

  assertEquals(result.error, null);
  assertExists(result.target);
  assertEquals(result.target.recipientId, "owner-2");
  assertEquals(result.target.recipientToken, "fcm-token-2");
});

Deno.test("loadNotificationTarget — follow_accepted resolves recipient from job.recipientId directly", async () => {
  const client = createMockClient({
    "profiles:id=requester-1": {
      data: { fcm_token: "fcm-token-r", display_name: "Requester" },
      error: null,
    },
    "profiles:id=accepter-1": {
      data: { display_name: "Accepter" },
      error: null,
    },
  });

  const job = {
    eventType: "follow_accepted" as const,
    actorId: "accepter-1",
    recipientId: "requester-1",
  };
  const result = await loadNotificationTarget(client, job);

  assertEquals(result.error, null);
  assertExists(result.target);
  assertEquals(result.target.recipientId, "requester-1");
  assertEquals(result.target.recipientToken, "fcm-token-r");
  assertEquals(result.target.actorDisplayName, "Accepter");
});

Deno.test("loadNotificationTarget — null fcm_token returns no-op (target=null, error=null)", async () => {
  const client = createMockClient({
    "activities:id=act-1": {
      data: { user_id: "owner-1" },
      error: null,
    },
    "profiles:id=owner-1": {
      data: { fcm_token: null, display_name: "Alice" },
      error: null,
    },
    "profiles:id=actor-1": {
      data: { display_name: "Bob" },
      error: null,
    },
  });

  const job = {
    eventType: "kudos" as const,
    actorId: "actor-1",
    activityId: "act-1",
  };
  const result = await loadNotificationTarget(client, job);
  assertEquals(result.target, null);
  assertEquals(result.error, null);
});

Deno.test("loadNotificationTarget — missing activity returns no-op (target=null, error=null)", async () => {
  const client = createMockClient({
    // No activities entry — simulates deleted/missing activity
  });

  const job = {
    eventType: "kudos" as const,
    actorId: "actor-1",
    activityId: "missing-act",
  };
  const result = await loadNotificationTarget(client, job);
  assertEquals(result.target, null);
  assertEquals(result.error, null);
});

// ===========================================================================
// Bug fix: lookup errors distinguished from no-ops
// ===========================================================================

Deno.test("loadNotificationTarget — activities query error returns error result, not null no-op", async () => {
  const client = createMockClient({
    "activities:id=act-1": {
      data: null,
      error: { message: "connection refused" },
    },
  });

  const job = {
    eventType: "kudos" as const,
    actorId: "actor-1",
    activityId: "act-1",
  };
  const result = await loadNotificationTarget(client, job);
  assertEquals(result.target, null);
  assertExists(result.error);
  assertEquals(result.error.includes("activities lookup failed"), true);
});

Deno.test("loadNotificationTarget — profiles query error returns error result, not null no-op", async () => {
  const client = createMockClient({
    "activities:id=act-1": {
      data: { user_id: "owner-1" },
      error: null,
    },
    "profiles:id=owner-1": {
      data: null,
      error: { message: "timeout" },
    },
  });

  const job = {
    eventType: "kudos" as const,
    actorId: "actor-1",
    activityId: "act-1",
  };
  const result = await loadNotificationTarget(client, job);
  assertEquals(result.target, null);
  assertExists(result.error);
  assertEquals(result.error.includes("profiles lookup failed"), true);
});

Deno.test("loadNotificationTarget — follow_accepted with profile query error returns error result", async () => {
  const client = createMockClient({
    "profiles:id=requester-1": {
      data: null,
      error: { message: "service unavailable" },
    },
  });

  const job = {
    eventType: "follow_accepted" as const,
    actorId: "accepter-1",
    recipientId: "requester-1",
  };
  const result = await loadNotificationTarget(client, job);
  assertEquals(result.target, null);
  assertExists(result.error);
  assertEquals(result.error.includes("profiles lookup failed"), true);
});
