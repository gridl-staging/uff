#!/usr/bin/env node
// SPIKE: Stage 6 — Beacon receiver prototype.
// Authenticates as the "other" test principal (different user from sender),
// subscribes to a Realtime Broadcast channel, and logs incoming GPS payloads
// with latency data.
//
// Usage:
//   BEACON_SESSION_ID=<id-from-sender> node supabase/tests/stage6_beacon_receiver.js
//
// Environment:
//   BEACON_SESSION_ID   — required, from sender output
//   BEACON_TIMEOUT_MS   — listen duration in ms (default: 120000)
//   BEACON_OUTPUT_FILE   — write raw JSON results to this path
//   SUPABASE_URL        — API base URL  (default: local)
//   SUPABASE_ANON_KEY   — publishable key (default: local)

import { writeFileSync } from 'fs'
import {
  OTHER_EMAIL,
  OTHER_PASSWORD,
  channelName,
  computeLatencyStats,
  formatReceiverGpsLogLine,
  parsePositiveInteger,
  createAuthenticatedClient,
  teardownRealtimeChannel,
  waitForSubscription,
} from './stage6_beacon_config.js'

function readReceiverOptions() {
  const sessionId = process.env.BEACON_SESSION_ID
  if (!sessionId) {
    throw new Error('BEACON_SESSION_ID required — get it from sender output')
  }

  return {
    sessionId,
    timeoutMs: parsePositiveInteger(process.env.BEACON_TIMEOUT_MS, 'BEACON_TIMEOUT_MS', 120000),
    outputFile: process.env.BEACON_OUTPUT_FILE || null,
  }
}

async function main() {
  const { sessionId, timeoutMs, outputFile } = readReceiverOptions()
  const { client: supabase, user } = await createAuthenticatedClient(OTHER_EMAIL, OTHER_PASSWORD)
  console.log(`Authenticated as ${OTHER_EMAIL} (${user.id})`)
  console.log(`Subscribing to ${channelName(sessionId)}`)
  console.log(`Listening for ${timeoutMs / 1000}s\n`)

  const received = []
  const channel = supabase.channel(channelName(sessionId))

  channel.on('broadcast', { event: 'gps' }, ({ payload }) => {
    const receiveTs = Date.now()
    const latencyMs = receiveTs - payload.ts
    received.push({ seq: payload.seq, sendTs: payload.ts, receiveTs, latencyMs })
    console.log(formatReceiverGpsLogLine(payload, receiveTs))
  })

  await waitForSubscription(channel)
  console.log('Subscription confirmed — waiting for messages\n')

  await new Promise((r) => setTimeout(r, timeoutMs))

  printSummary(received, outputFile)
  await teardownRealtimeChannel(supabase, channel)
  process.exit(0)
}

function printSummary(received, outputFile) {
  console.log('\n--- Summary ---')
  if (received.length === 0) {
    console.log('No messages received')
    return
  }
  const stats = computeLatencyStats(received)
  console.log(`Messages received: ${stats.count}`)
  console.log(`Median latency:    ${stats.median}ms`)
  console.log(`P95 latency:       ${stats.p95}ms`)
  console.log(`Max latency:       ${stats.max}ms`)
  console.log(`In order:          ${stats.inOrder}`)

  if (outputFile) {
    writeFileSync(outputFile, JSON.stringify({ received, summary: stats }, null, 2))
    console.log(`Raw data written to ${outputFile}`)
  }
}

main().catch((err) => {
  console.error('Fatal:', err)
  process.exit(1)
})
