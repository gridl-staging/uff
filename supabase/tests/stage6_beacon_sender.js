#!/usr/bin/env node
// SPIKE: Stage 6 — Beacon sender prototype.
// Authenticates as the owner test principal, connects to a Realtime Broadcast
// channel, and streams simulated GPS payloads at a configurable interval.
//
// Usage:
//   node supabase/tests/stage6_beacon_sender.js
//
// Environment:
//   BEACON_SESSION_ID    — channel session id (default: random UUID)
//   BEACON_INTERVAL_MS   — send interval in ms  (default: 5000)
//   BEACON_MESSAGE_COUNT — number of messages    (default: 15)
//   SUPABASE_URL         — API base URL          (default: local)
//   SUPABASE_ANON_KEY    — publishable key       (default: local)

import {
  OWNER_EMAIL,
  OWNER_PASSWORD,
  DEFAULT_INTERVAL_MS,
  DEFAULT_MESSAGE_COUNT,
  channelName,
  gpsPayload,
  parsePositiveInteger,
  createAuthenticatedClient,
  sendBroadcastEvent,
  teardownRealtimeChannel,
  waitForSubscription,
  sleep,
} from './stage6_beacon_config.js'

function readSenderOptions() {
  return {
    sessionId: process.env.BEACON_SESSION_ID || crypto.randomUUID(),
    intervalMs: parsePositiveInteger(
      process.env.BEACON_INTERVAL_MS,
      'BEACON_INTERVAL_MS',
      DEFAULT_INTERVAL_MS
    ),
    messageCount: parsePositiveInteger(
      process.env.BEACON_MESSAGE_COUNT,
      'BEACON_MESSAGE_COUNT',
      DEFAULT_MESSAGE_COUNT
    ),
  }
}

async function main() {
  const { sessionId, intervalMs, messageCount } = readSenderOptions()
  const { client: supabase, user } = await createAuthenticatedClient(OWNER_EMAIL, OWNER_PASSWORD)
  console.log(`Authenticated as ${OWNER_EMAIL} (${user.id})`)
  console.log(`Channel: ${channelName(sessionId)}`)
  console.log(`Sending ${messageCount} messages at ${intervalMs}ms intervals\n`)

  const channel = supabase.channel(channelName(sessionId))
  await waitForSubscription(channel)
  console.log('Subscription confirmed — starting beacon transmission\n')

  for (let seq = 1; seq <= messageCount; seq++) {
    const payload = gpsPayload(seq)
    await sendBroadcastEvent(channel, 'gps', payload)
    console.log(
      `[${new Date().toISOString()}] seq=${seq} result=ok ` +
        `lat=${payload.lat.toFixed(6)} lon=${payload.lon.toFixed(6)}`
    )
    if (seq < messageCount) await sleep(intervalMs)
  }

  console.log('\nTransmission complete — unsubscribing')
  await teardownRealtimeChannel(supabase, channel)
  console.log('Disconnected cleanly')
  process.exit(0)
}

main().catch((err) => {
  console.error('Fatal:', err)
  process.exit(1)
})
