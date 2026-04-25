// SPIKE: Stage 6 — Shared beacon configuration and utilities.
// Not production code. Validates Supabase Realtime Broadcast for GPS beacon.

import { existsSync, readFileSync } from 'fs'
import { createClient } from '@supabase/supabase-js'

// ---------------------------------------------------------------------------
// Supabase connection (env vars override local defaults)
// ---------------------------------------------------------------------------

const DEFAULT_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.' +
  'eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.' +
  'CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0'

export const SUPABASE_URL = process.env.SUPABASE_URL || 'http://127.0.0.1:54321'
export const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || DEFAULT_ANON_KEY

// ---------------------------------------------------------------------------
// Stage 3 test principals
// ---------------------------------------------------------------------------

const DEFAULT_STAGE3_PRINCIPALS = Object.freeze({
  owner: Object.freeze({
    email: 'rls-owner@test.local',
    password: 'RlsOwnerPass!42',
  }),
  other: Object.freeze({
    email: 'rls-other@test.local',
    password: 'RlsOtherPass!42',
  }),
})

function loadStage3Principals() {
  const principalsPath = new URL('./stage3_test_principals.json', import.meta.url)
  if (!existsSync(principalsPath)) {
    return DEFAULT_STAGE3_PRINCIPALS
  }

  const parsedFile = JSON.parse(readFileSync(principalsPath, 'utf8'))
  const owner = parsedFile?.principals?.owner
  const other = parsedFile?.principals?.other
  if (
    typeof owner?.email !== 'string' ||
    typeof owner?.password !== 'string' ||
    typeof other?.email !== 'string' ||
    typeof other?.password !== 'string'
  ) {
    throw new Error('stage3_test_principals.json is missing owner/other email/password fields')
  }

  return {
    owner: { email: owner.email, password: owner.password },
    other: { email: other.email, password: other.password },
  }
}

const STAGE3_PRINCIPALS = loadStage3Principals()

export const OWNER_EMAIL = STAGE3_PRINCIPALS.owner.email
export const OWNER_PASSWORD = STAGE3_PRINCIPALS.owner.password
export const OTHER_EMAIL = STAGE3_PRINCIPALS.other.email
export const OTHER_PASSWORD = STAGE3_PRINCIPALS.other.password

// ---------------------------------------------------------------------------
// Beacon defaults
// ---------------------------------------------------------------------------

export const DEFAULT_INTERVAL_MS = 5000
export const DEFAULT_MESSAGE_COUNT = 15
export const CHANNEL_PREFIX = 'beacon'

export function channelName(sessionId) {
  return `${CHANNEL_PREFIX}:${sessionId}`
}

export function parsePositiveInteger(rawValue, envName, defaultValue) {
  const hasExplicitValue = rawValue !== undefined && rawValue !== null && rawValue !== ''
  if (!hasExplicitValue) {
    if (!Number.isSafeInteger(defaultValue) || defaultValue <= 0) {
      throw new Error(`${envName} must be a positive integer`)
    }
    return defaultValue
  }

  const normalizedValue = String(rawValue).trim()
  if (!/^[0-9]+$/.test(normalizedValue)) {
    throw new Error(`${envName} must be a positive integer`)
  }

  const resolvedValue = Number(normalizedValue)
  if (!Number.isSafeInteger(resolvedValue) || resolvedValue <= 0) {
    throw new Error(`${envName} must be a positive integer`)
  }

  return resolvedValue
}

// ---------------------------------------------------------------------------
// Simulated GPS payload — compact field names to minimize message size.
//
// Fields per update:
//   lat  — latitude (decimal degrees)
//   lon  — longitude (decimal degrees)
//   ts   — sender timestamp (epoch ms)
//   acc  — GPS accuracy (meters)
//   spd  — speed (m/s)
//   brg  — bearing (degrees)
//   seq  — monotonic sequence number
//
// ~100 bytes per message. At 5 s intervals: ~1.2 KB/min, well under current
// hosted Supabase Broadcast payload and throughput limits.
//
// Session-level metadata (activity type, display name, share token) is NOT
// included in repeated GPS messages. It belongs in a one-time session_info
// event or an out-of-band API lookup by session_id.
// ---------------------------------------------------------------------------

const BASE_LAT = 37.7749
const BASE_LON = -122.4194

export function gpsPayload(seq) {
  return {
    lat: BASE_LAT + (Math.random() - 0.5) * 0.001,
    lon: BASE_LON + (Math.random() - 0.5) * 0.001,
    ts: Date.now(),
    acc: +(3 + Math.random() * 10).toFixed(1),
    spd: +(1 + Math.random() * 5).toFixed(1),
    brg: +(Math.random() * 360).toFixed(0),
    seq,
  }
}

// ---------------------------------------------------------------------------
// Latency statistics
// ---------------------------------------------------------------------------

export function computeLatencyStats(received) {
  if (received.length === 0) return null
  const latencies = received.map((r) => r.latencyMs).sort((a, b) => a - b)
  const seqs = received.map((r) => r.seq)
  const inOrder = seqs.every((s, i) => i === 0 || s > seqs[i - 1])
  return {
    count: received.length,
    median: latencies[Math.floor(latencies.length / 2)],
    p95: latencies[Math.floor(latencies.length * 0.95)],
    max: latencies[latencies.length - 1],
    min: latencies[0],
    inOrder,
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

export function waitForSubscription(channel) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Subscription timeout')), 10000)
    channel.subscribe((status) => {
      if (status === 'SUBSCRIBED') {
        clearTimeout(timeout)
        resolve()
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
        clearTimeout(timeout)
        reject(new Error(`Subscription failed: ${status}`))
      }
    })
  })
}

export function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms))
}

export function formatAuthFailureMessage(email, authMessage) {
  const reprovisionHint =
    authMessage === 'Invalid login credentials'
      ? ' Run ./supabase/tests/stage3_provision_test_principals.sh after supabase db reset --local to recreate the Stage 3 principals.'
      : ''
  return `Auth failed for ${email}: ${authMessage}${reprovisionHint}`
}

export async function createAuthenticatedClient(email, password) {
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  const { data, error } = await client.auth.signInWithPassword({ email, password })
  if (error) throw new Error(formatAuthFailureMessage(email, error.message))
  if (!data.user) throw new Error(`Auth failed for ${email}: user missing from response`)
  return { client, user: data.user }
}

export async function sendBroadcastEvent(channel, event, payload) {
  const result = await channel.send({ type: 'broadcast', event, payload })
  if (result !== 'ok') {
    throw new Error(`Broadcast send failed: ${result}`)
  }
  return result
}

export async function teardownRealtimeChannel(client, channel) {
  let removeStatus = null
  try {
    removeStatus = await client.removeChannel(channel)
  } finally {
    client.realtime.disconnect()
  }

  if (removeStatus !== 'ok') {
    throw new Error(`Channel teardown failed: ${removeStatus}`)
  }
}

export function formatReceiverGpsLogLine(payload, receiveTs) {
  const senderTimestampIso = new Date(payload.ts).toISOString()
  const receiverTimestampIso = new Date(receiveTs).toISOString()
  const latencyMs = receiveTs - payload.ts
  return (
    `[${receiverTimestampIso}] seq=${payload.seq} senderTs=${senderTimestampIso} ` +
    `latency=${latencyMs}ms lat=${payload.lat.toFixed(6)} lon=${payload.lon.toFixed(6)}`
  )
}
