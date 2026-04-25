/**
 * @module Stub summary for index.ts.
 */
// send-notification Edge Function
//
// Supabase Database Webhooks call this function on inserts to kudos/comments
// and on follows status transitions (pending → accepted). All notification
// routing, recipient lookup, FCM delivery, and stale-token cleanup live here
// so push behavior has one backend-owned source of truth.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface WebhookPayload {
  type: string;
  table: string;
  schema: string;
  record: Record<string, unknown>;
  old_record: Record<string, unknown>;
}

// Activity-scoped events (kudos, comment) need a DB lookup for the recipient.
interface ActivityNotificationJob {
  eventType: "kudos" | "comment";
  actorId: string;
  activityId: string;
}

// Follow-accept events carry the recipient directly in the webhook payload.
interface FollowNotificationJob {
  eventType: "follow_accepted";
  actorId: string;
  recipientId: string;
}

export type NotificationJob = ActivityNotificationJob | FollowNotificationJob;

export interface NotificationTarget {
  recipientId: string;
  recipientToken: string;
  actorDisplayName: string;
}

interface NotificationConfig {
  supabaseUrl: string;
  serviceRoleKey: string;
  webhookSecret: string;
  fcmProjectId: string;
  fcmClientEmail: string;
  fcmPrivateKey: string;
}

export interface FcmMessageParams {
  projectId: string;
  accessToken: string;
  recipientToken: string;
  title: string;
  body: string;
}

// Discriminated result from loadNotificationTarget: error means a DB query
// failed (should retry), target=null+error=null means a legitimate no-op.
export interface LoadTargetResult {
  target: NotificationTarget | null;
  error: string | null;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "Authorization, Content-Type, apikey, x-webhook-secret",
};
const WEBHOOK_SECRET_HEADER = "x-webhook-secret";

// FCM error codes that indicate the token is permanently invalid.
const STALE_TOKEN_ERROR_CODES = new Set(["UNREGISTERED", "INVALID_ARGUMENT"]);

// ---------------------------------------------------------------------------
// Helpers — pure
// ---------------------------------------------------------------------------

export function jsonResponse(
  body: Record<string, unknown>,
  status: number,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/**
 * Route a Supabase Database Webhook payload to a notification job.
 *
 * Returns null for unsupported table/operation combinations or payloads
 * missing required fields. The supported webhook matrix is encoded here
 * (and tested in index_test.ts) rather than in a separate document.
 */
export function buildNotificationJob(
  payload: WebhookPayload,
): NotificationJob | null {
  const { type, table, record, old_record } = payload;

  // kudos INSERT or comments INSERT → activity-scoped notification
  if (
    type === "INSERT" &&
    (table === "kudos" || table === "comments")
  ) {
    const activityId = record.activity_id;
    const actorId = record.user_id;
    if (typeof activityId !== "string" || typeof actorId !== "string") {
      return null;
    }
    const eventType = table === "kudos" ? "kudos" : "comment";
    return { eventType, actorId, activityId } as ActivityNotificationJob;
  }

  // follows UPDATE: only route the pending → accepted transition
  if (type === "UPDATE" && table === "follows") {
    const oldStatus = old_record?.status;
    const newStatus = record.status;
    if (oldStatus !== "pending" || newStatus !== "accepted") {
      return null;
    }
    const actorId = record.following_id;
    const recipientId = record.follower_id;
    if (typeof actorId !== "string" || typeof recipientId !== "string") {
      return null;
    }
    return {
      eventType: "follow_accepted",
      actorId,
      recipientId,
    } as FollowNotificationJob;
  }

  return null;
}

/**
 * Returns true when the notification should be suppressed because the
 * actor and recipient are the same user.
 */
export function shouldSkipNotification(
  actorId: string,
  recipientId: string,
): boolean {
  return actorId === recipientId;
}

// ---------------------------------------------------------------------------
// Helpers — config
// ---------------------------------------------------------------------------

/**
 * TODO: Document loadNotificationConfig.
 */
export function loadNotificationConfig(): NotificationConfig | null {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const webhookSecret = Deno.env.get("NOTIFICATION_WEBHOOK_SECRET");
  const fcmProjectId = Deno.env.get("FCM_PROJECT_ID");
  const fcmClientEmail = Deno.env.get("FCM_CLIENT_EMAIL");
  const rawFcmPrivateKey = Deno.env.get("FCM_PRIVATE_KEY");
  const fcmPrivateKey = rawFcmPrivateKey?.replace(/\\n/g, "\n");

  if (
    !supabaseUrl || !serviceRoleKey || !webhookSecret || !fcmProjectId ||
    !fcmClientEmail || !fcmPrivateKey
  ) {
    return null;
  }

  return {
    supabaseUrl,
    serviceRoleKey,
    webhookSecret,
    fcmProjectId,
    fcmClientEmail,
    fcmPrivateKey,
  };
}

export function hasAuthorizedWebhookSecret(
  req: Request,
  webhookSecret: string,
): boolean {
  const providedSecret = req.headers.get(WEBHOOK_SECRET_HEADER);
  return providedSecret != null && providedSecret === webhookSecret;
}

// ---------------------------------------------------------------------------
// Helpers — DB-dependent
// ---------------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
type SupabaseClient = any;
type CreateClientFn = (
  supabaseUrl: string,
  serviceRoleKey: string,
) => SupabaseClient;

/**
 * TODO: Document NotificationRequestDependencies.
 */
export interface NotificationRequestDependencies {
  createClientFn?: CreateClientFn;
  loadNotificationConfigFn?: () => NotificationConfig | null;
  buildNotificationJobFn?: (payload: WebhookPayload) => NotificationJob | null;
  loadNotificationTargetFn?: (
    client: SupabaseClient,
    job: NotificationJob,
  ) => Promise<LoadTargetResult>;
  shouldSkipNotificationFn?: (actorId: string, recipientId: string) => boolean;
  mintFcmAccessTokenFn?: (
    clientEmail: string,
    privateKeyPem: string,
  ) => Promise<string>;
  sendFcmMessageFn?: (
    params: FcmMessageParams,
    fetchFn?: typeof fetch,
  ) => Promise<Response>;
  handleFcmResponseFn?: (
    client: SupabaseClient,
    recipientId: string,
    recipientToken: string,
    response: Response,
  ) => Promise<{ tokenCleared: boolean; cleanupError: string | null }>;
}

interface DeliveryContext {
  client: SupabaseClient;
  config: NotificationConfig;
  job: NotificationJob;
  target: NotificationTarget;
}

/**
 * Resolve the notification recipient and actor display name from the database.
 *
 * For kudos/comment events, the recipient is the activity owner
 * (activities.user_id). For follow_accepted events, the recipient is
 * record.follower_id (already on the job). Returns null when the recipient
 * has no fcm_token or the referenced activity is missing.
 */
export async function loadNotificationTarget(
  client: SupabaseClient,
  job: NotificationJob,
): Promise<LoadTargetResult> {
  let recipientId: string;

  if (job.eventType === "follow_accepted") {
    recipientId = job.recipientId;
  } else {
    // Look up the activity owner for kudos/comment events
    const { data: activity, error: activityError } = await client
      .from("activities")
      .select("user_id")
      .eq("id", job.activityId)
      .single();

    if (activityError) {
      return {
        target: null,
        error: `activities lookup failed: ${activityError.message}`,
      };
    }
    if (!activity?.user_id) {
      return { target: null, error: null };
    }
    recipientId = activity.user_id as string;
  }

  // Fetch recipient's FCM token
  const { data: recipientProfile, error: profileError } = await client
    .from("profiles")
    .select("fcm_token, display_name")
    .eq("id", recipientId)
    .single();

  if (profileError) {
    return {
      target: null,
      error: `profiles lookup failed: ${profileError.message}`,
    };
  }
  if (!recipientProfile?.fcm_token) {
    return { target: null, error: null };
  }

  // Fetch actor display name for the notification text
  const { data: actorProfile } = await client
    .from("profiles")
    .select("display_name")
    .eq("id", job.actorId)
    .single();

  const actorDisplayName = (actorProfile?.display_name as string) ?? "Someone";

  return {
    target: {
      recipientId,
      recipientToken: recipientProfile.fcm_token as string,
      actorDisplayName,
    },
    error: null,
  };
}

// ---------------------------------------------------------------------------
// Helpers — FCM delivery
// ---------------------------------------------------------------------------

function base64urlEncode(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/,
    "",
  );
}

/**
 * Mint a short-lived Google OAuth2 access token from a service-account
 * private key, scoped to Firebase Cloud Messaging.
 */
export async function mintFcmAccessToken(
  clientEmail: string,
  privateKeyPem: string,
): Promise<string> {
  const pemBody = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const keyData = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const now = Math.floor(Date.now() / 1000);
  const header = base64urlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64urlEncode(JSON.stringify({
    iss: clientEmail,
    sub: clientEmail,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  }));

  const signingInput = new TextEncoder().encode(`${header}.${payload}`);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    signingInput,
  );

  const jwt = `${header}.${payload}.${base64urlEncode(signature)}`;

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body:
      `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });

  const tokenData = await tokenResponse.json();
  if (!tokenData.access_token) {
    throw new Error(
      `Failed to mint FCM access token: ${JSON.stringify(tokenData)}`,
    );
  }
  return tokenData.access_token as string;
}

/**
 * Build the notification title/body for a given event type and actor name.
 */
function buildNotificationContent(
  eventType: string,
  actorDisplayName: string,
): { title: string; body: string } {
  switch (eventType) {
    case "kudos":
      return {
        title: "New Like",
        body: `${actorDisplayName} liked your activity`,
      };
    case "comment":
      return {
        title: "New Comment",
        body: `${actorDisplayName} commented on your activity`,
      };
    case "follow_accepted":
      return {
        title: "Follow Accepted",
        body: `${actorDisplayName} accepted your follow request`,
      };
    default:
      return { title: "Notification", body: "You have a new notification" };
  }
}

/**
 * Send one push notification via FCM HTTP v1. The request body is built in
 * this single shared code path — callers pass structured params rather than
 * assembling payloads ad hoc.
 */
export async function sendFcmMessage(
  params: FcmMessageParams,
  fetchFn: typeof fetch = fetch,
): Promise<Response> {
  const url =
    `https://fcm.googleapis.com/v1/projects/${params.projectId}/messages:send`;

  return fetchFn(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${params.accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: {
        token: params.recipientToken,
        notification: {
          title: params.title,
          body: params.body,
        },
      },
    }),
  });
}

/**
 * Inspect an FCM response and clear the recipient's fcm_token when the error
 * code indicates the token is permanently stale (UNREGISTERED or
 * INVALID_ARGUMENT). Transient errors (5xx, network failures) leave the
 * token intact so retries remain possible.
 */
export async function handleFcmResponse(
  client: SupabaseClient,
  recipientId: string,
  recipientToken: string,
  response: Response,
): Promise<{ tokenCleared: boolean; cleanupError: string | null }> {
  if (response.ok) {
    return { tokenCleared: false, cleanupError: null };
  }

  try {
    const body = await response.json();
    const details = body?.error?.details;
    if (Array.isArray(details)) {
      for (const detail of details) {
        if (STALE_TOKEN_ERROR_CODES.has(detail?.errorCode)) {
          const { data, error } = await client
            .from("profiles")
            .update({ fcm_token: null })
            .eq("id", recipientId)
            .eq("fcm_token", recipientToken)
            .select("id")
            .maybeSingle();

          if (error) {
            return {
              tokenCleared: false,
              cleanupError:
                `profiles stale-token cleanup failed: ${error.message}`,
            };
          }

          // If no row matched, the user rotated/cleared the token after the
          // delivery attempt. Do not claim cleanup succeeded for a different
          // token value.
          return {
            tokenCleared: Boolean(data?.id),
            cleanupError: null,
          };
        }
      }
    }
  } catch {
    // Unparseable response body — treat as transient
  }

  return { tokenCleared: false, cleanupError: null };
}

/**
 * TODO: Document deliverNotification.
 */
async function deliverNotification(
  context: DeliveryContext,
  deps: Pick<
    NotificationRequestDependencies,
    "mintFcmAccessTokenFn" | "sendFcmMessageFn" | "handleFcmResponseFn"
  >,
): Promise<Response> {
  const {
    client,
    config,
    job,
    target,
  } = context;
  const {
    mintFcmAccessTokenFn = mintFcmAccessToken,
    sendFcmMessageFn = sendFcmMessage,
    handleFcmResponseFn = handleFcmResponse,
  } = deps;

  try {
    const accessToken = await mintFcmAccessTokenFn(
      config.fcmClientEmail,
      config.fcmPrivateKey,
    );
    const content = buildNotificationContent(
      job.eventType,
      target.actorDisplayName,
    );
    const fcmResponse = await sendFcmMessageFn({
      projectId: config.fcmProjectId,
      accessToken,
      recipientToken: target.recipientToken,
      title: content.title,
      body: content.body,
    });
    const { tokenCleared, cleanupError } = await handleFcmResponseFn(
      client,
      target.recipientId,
      target.recipientToken,
      fcmResponse,
    );

    if (cleanupError) {
      return jsonResponse(
        { error: "Stale token cleanup failed", detail: cleanupError },
        500,
      );
    }
    if (fcmResponse.ok) {
      return jsonResponse({ sent: true }, 200);
    }
    if (tokenCleared) {
      return jsonResponse({
        sent: false,
        tokenCleared: true,
        fcmStatus: fcmResponse.status,
      }, 200);
    }

    return jsonResponse({
      sent: false,
      tokenCleared: false,
      fcmStatus: fcmResponse.status,
    }, 502);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return jsonResponse(
      { error: "FCM delivery failed", detail: message },
      500,
    );
  }
}

// ---------------------------------------------------------------------------
// Main handler — only runs when this file is the Deno entry point
// ---------------------------------------------------------------------------

/**
 * TODO: Document handleNotificationRequest.
 */
export async function handleNotificationRequest(
  req: Request,
  deps: NotificationRequestDependencies = {},
): Promise<Response> {
  const {
    createClientFn = createClient as CreateClientFn,
    loadNotificationConfigFn = loadNotificationConfig,
    buildNotificationJobFn = buildNotificationJob,
    loadNotificationTargetFn = loadNotificationTarget,
    shouldSkipNotificationFn = shouldSkipNotification,
    mintFcmAccessTokenFn = mintFcmAccessToken,
    sendFcmMessageFn = sendFcmMessage,
    handleFcmResponseFn = handleFcmResponse,
  } = deps;

  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // Load function configuration before any privileged work.
  const config = loadNotificationConfigFn();
  if (!config) {
    return jsonResponse(
      { error: "Function configuration is incomplete" },
      500,
    );
  }

  if (!hasAuthorizedWebhookSecret(req, config.webhookSecret)) {
    return jsonResponse({ error: "Unauthorized webhook request" }, 401);
  }

  // Parse webhook payload
  let payload: WebhookPayload;
  try {
    payload = await req.json() as WebhookPayload;
  } catch {
    return jsonResponse({ error: "Invalid JSON payload" }, 400);
  }

  // Route the webhook to a notification job
  const job = buildNotificationJobFn(payload);
  if (!job) {
    return jsonResponse({ skipped: true, reason: "unsupported_event" }, 200);
  }

  const client = createClientFn(config.supabaseUrl, config.serviceRoleKey);

  // Resolve recipient and actor info
  const { target, error: lookupError } = await loadNotificationTargetFn(
    client,
    job,
  );
  if (lookupError) {
    // Service-role query failed — return 500 so webhooks retry
    return jsonResponse(
      { error: "Recipient lookup failed", detail: lookupError },
      500,
    );
  }
  if (!target) {
    return jsonResponse(
      { skipped: true, reason: "no_recipient_token" },
      200,
    );
  }

  // Suppress self-notifications
  if (shouldSkipNotificationFn(job.actorId, target.recipientId)) {
    return jsonResponse(
      { skipped: true, reason: "self_notification" },
      200,
    );
  }

  return deliverNotification(
    { client, config, job, target },
    {
      mintFcmAccessTokenFn,
      sendFcmMessageFn,
      handleFcmResponseFn,
    },
  );
}

if (import.meta.main) {
  Deno.serve((req: Request): Promise<Response> =>
    handleNotificationRequest(req)
  );
}
