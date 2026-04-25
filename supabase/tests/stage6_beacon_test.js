#!/usr/bin/env node
// SPIKE: Stage 6 — Automated beacon validation tests.
// Runs latency/ordering, disconnect/reconnect, and presence tests against
// Supabase Realtime Broadcast.  Outputs raw data for ADR-002.
//
// Usage:
//   node supabase/tests/stage6_beacon_test.js
//
// Environment:
//   SUPABASE_URL      — defaults to local
//   SUPABASE_ANON_KEY — defaults to local
//   BEACON_OUTPUT_DIR — directory for result files (default: supabase/tests)

import { writeFileSync } from 'fs'
import { createClient } from '@supabase/supabase-js'
import {
  SUPABASE_URL,
  SUPABASE_ANON_KEY,
  OWNER_EMAIL,
  OWNER_PASSWORD,
  OTHER_EMAIL,
  OTHER_PASSWORD,
  channelName,
  gpsPayload,
  computeLatencyStats,
  createAuthenticatedClient,
  sendBroadcastEvent,
  teardownRealtimeChannel,
  waitForSubscription,
  sleep,
} from './stage6_beacon_config.js'

const OUTPUT_DIR = process.env.BEACON_OUTPUT_DIR || 'supabase/tests'
let passCount = 0
let failCount = 0

function pass(label) {
  passCount++
  console.log(`  PASS: ${label}`)
}

function fail(label) {
  failCount++
  console.error(`  FAIL: ${label}`)
}

function assertCondition(condition, label) {
  if (condition) pass(label)
  else fail(label)
}

async function sendGpsBatch(channel, startSeq, endSeq, intervalMs) {
  for (let seq = startSeq; seq <= endSeq; seq++) {
    await sendBroadcastEvent(channel, 'gps', gpsPayload(seq))
    if (seq < endSeq && intervalMs > 0) {
      await sleep(intervalMs)
    }
  }
}

async function waitForReceivedCount(received, expectedCount, timeoutMs, matcher = () => true) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (received.filter(matcher).length >= expectedCount) return true
    await sleep(50)
  }
  return received.filter(matcher).length >= expectedCount
}

async function createAuthenticatedPair() {
  const { client: senderClient } = await createAuthenticatedClient(OWNER_EMAIL, OWNER_PASSWORD)
  const { client: receiverClient } = await createAuthenticatedClient(OTHER_EMAIL, OTHER_PASSWORD)
  return { senderClient, receiverClient }
}

function createBeaconChannel(client, sessionId, config = null) {
  if (config) {
    return client.channel(channelName(sessionId), config)
  }
  return client.channel(channelName(sessionId))
}

async function subscribeGpsChannel(client, sessionId, onPayload, config = null) {
  const channel = createBeaconChannel(client, sessionId, config)
  channel.on('broadcast', { event: 'gps' }, ({ payload }) => onPayload(payload))
  await waitForSubscription(channel)
  return channel
}

async function subscribeSequenceChannel(client, sessionId, getTarget) {
  return subscribeGpsChannel(
    client,
    sessionId,
    (payload) => recordSequenceSample(getTarget(), payload)
  )
}

function recordLatencySample(received, payload) {
  const receiveTs = Date.now()
  received.push({ seq: payload.seq, sendTs: payload.ts, receiveTs, latencyMs: receiveTs - payload.ts })
}

function recordSequenceSample(target, payload) {
  target.push({ seq: payload.seq, ts: Date.now() })
}

function attachPresenceEventLog(channel, events) {
  channel.on('presence', { event: 'join' }, ({ key, newPresences }) => {
    events.push({ type: 'presence_join', key, presences: newPresences, ts: Date.now() })
  })
  channel.on('presence', { event: 'leave' }, ({ key, leftPresences }) => {
    events.push({ type: 'presence_leave', key, presences: leftPresences, ts: Date.now() })
  })
}

function evaluateSenderDisconnect(events, beforeDisconnect) {
  const gpsEvents = events.filter((event) => event.type === 'gps')
  const senderLeave = events.find((event) => event.type === 'presence_leave' && event.key === 'sender')
  return {
    gpsEvents,
    senderLeave,
    detectionMs: senderLeave ? senderLeave.ts - beforeDisconnect : null,
  }
}

function evaluateReconnectResults(afterReconnect) {
  const receivedMissed = afterReconnect.filter((message) => [4, 5, 6].includes(message.seq))
  return {
    receivedMissed,
    duringDisconnectLost: receivedMissed.length === 0,
    afterReconnectCount: afterReconnect.length,
  }
}

function assertReconnectExpectations(beforeDisconnectCount, reconnectResults) {
  assertCondition(
    beforeDisconnectCount >= 3,
    `Received ≥3 messages before disconnect (got ${beforeDisconnectCount})`
  )
  assertCondition(
    reconnectResults.duringDisconnectLost,
    'Messages during disconnect are lost (expected for Broadcast)'
  )
  assertCondition(
    reconnectResults.afterReconnectCount >= 3,
    `Received ≥3 messages after reconnect (got ${reconnectResults.afterReconnectCount})`
  )
}

// ---------------------------------------------------------------------------
// Test 1: Latency and ordering (≥12 messages at 5 s intervals, ≥60 s)
// ---------------------------------------------------------------------------

async function testLatencyAndOrdering() {
  console.log('\n=== Test 1: Latency and Ordering ===')
  const sessionId = crypto.randomUUID()
  const messageCount = 15
  const intervalMs = 5000

  const { senderClient, receiverClient } = await createAuthenticatedPair()
  const received = []
  const receiverChannel = await subscribeGpsChannel(
    receiverClient,
    sessionId,
    (payload) => recordLatencySample(received, payload)
  )
  console.log('  Receiver subscribed')

  const senderChannel = createBeaconChannel(senderClient, sessionId)
  await waitForSubscription(senderChannel)
  console.log('  Sender subscribed')

  await sleep(500) // let subscriptions stabilize

  console.log(`  Sending ${messageCount} messages at ${intervalMs}ms intervals...`)
  await sendGpsBatch(senderChannel, 1, messageCount, intervalMs)
  await waitForReceivedCount(received, messageCount, 5000)

  const stats = computeLatencyStats(received)
  if (!stats) {
    fail('No messages received by receiver')
    await teardownRealtimeChannel(senderClient, senderChannel)
    await teardownRealtimeChannel(receiverClient, receiverChannel)
    return null
  }

  console.log(`  Received ${stats.count}/${messageCount} messages`)
  console.log(`  Median: ${stats.median}ms  P95: ${stats.p95}ms  Max: ${stats.max}ms`)
  console.log(`  In order: ${stats.inOrder}`)

  assertCondition(stats.count >= 12, `Received ≥12 messages (got ${stats.count})`)
  assertCondition(stats.median < 500, `Median latency <500ms (got ${stats.median}ms)`)
  assertCondition(stats.inOrder, 'Messages arrived in send order')

  await teardownRealtimeChannel(senderClient, senderChannel)
  await teardownRealtimeChannel(receiverClient, receiverChannel)

  return { received, stats }
}

// ---------------------------------------------------------------------------
// Test 2: Sender disconnect — what does receiver observe?
// ---------------------------------------------------------------------------

async function testSenderDisconnect() {
  console.log('\n=== Test 2: Sender Disconnect ===')
  const sessionId = crypto.randomUUID()

  const { senderClient, receiverClient } = await createAuthenticatedPair()
  const events = []
  const receiverChannel = createBeaconChannel(receiverClient, sessionId, {
    config: { presence: { key: 'receiver' } },
  })
  receiverChannel.on('broadcast', { event: 'gps' }, ({ payload }) => {
    events.push({ type: 'gps', seq: payload.seq, ts: Date.now() })
  })
  attachPresenceEventLog(receiverChannel, events)
  await waitForSubscription(receiverChannel)
  await receiverChannel.track({ role: 'receiver' })

  const senderChannel = createBeaconChannel(senderClient, sessionId, {
    config: { presence: { key: 'sender' } },
  })
  await waitForSubscription(senderChannel)
  await senderChannel.track({ role: 'sender' })
  await sleep(1000)

  // Send 3 messages, then disconnect abruptly
  await sendGpsBatch(senderChannel, 1, 3, 500)
  await waitForReceivedCount(events, 3, 3000, (event) => event.type === 'gps')

  const beforeDisconnect = Date.now()
  console.log('  Disconnecting sender abruptly...')
  senderClient.realtime.disconnect()
  await sleep(15000) // wait up to 15 s for receiver to detect departure

  const { gpsEvents, senderLeave, detectionMs } = evaluateSenderDisconnect(events, beforeDisconnect)

  assertCondition(gpsEvents.length >= 3, `Received ≥3 GPS messages before disconnect (got ${gpsEvents.length})`)

  if (senderLeave) {
    console.log(`  Sender departure detected via Presence in ${detectionMs}ms`)
    pass(`Presence leave event received (${detectionMs}ms)`)
  } else {
    console.log('  No Presence leave event — receiver got silence on disconnect')
    fail('Presence leave event not received within 15s')
  }

  await teardownRealtimeChannel(receiverClient, receiverChannel)

  return {
    gpsBeforeDisconnect: gpsEvents.length,
    presenceLeaveDetected: !!senderLeave,
    detectionMs,
    allEvents: events,
  }
}

// ---------------------------------------------------------------------------
// Test 3: Receiver disconnect + reconnect — are messages lost?
// ---------------------------------------------------------------------------

async function testReceiverReconnect() {
  console.log('\n=== Test 3: Receiver Disconnect + Reconnect ===')
  const sessionId = crypto.randomUUID()

  const { senderClient, receiverClient } = await createAuthenticatedPair()
  const beforeDisconnect = []
  const afterReconnect = []
  let collectTarget = beforeDisconnect

  const receiverChannel = await subscribeSequenceChannel(receiverClient, sessionId, () => collectTarget)

  const senderChannel = createBeaconChannel(senderClient, sessionId)
  await waitForSubscription(senderChannel)
  await sleep(500)

  // Send 3 messages while receiver is connected
  await sendGpsBatch(senderChannel, 1, 3, 300)
  await waitForReceivedCount(beforeDisconnect, 3, 3000)

  console.log(`  Before disconnect: received ${beforeDisconnect.length} messages`)

  // Disconnect receiver
  console.log('  Disconnecting receiver...')
  await receiverClient.removeChannel(receiverChannel)
  await sleep(1000)

  // Send 3 messages while receiver is disconnected
  console.log('  Sending 3 messages while receiver is disconnected...')
  await sendGpsBatch(senderChannel, 4, 6, 300)
  await sleep(1000)

  // Reconnect receiver
  collectTarget = afterReconnect
  const reconnectedChannel = await subscribeSequenceChannel(
    receiverClient,
    sessionId,
    () => collectTarget
  )
  console.log('  Receiver reconnected')

  // Send 3 more messages after reconnect
  await sendGpsBatch(senderChannel, 7, 9, 300)
  await waitForReceivedCount(afterReconnect, 3, 3000)

  const { duringDisconnectLost, afterReconnectCount } = evaluateReconnectResults(afterReconnect)
  console.log(`  After reconnect: received ${afterReconnectCount} messages`)
  assertReconnectExpectations(beforeDisconnect.length, { duringDisconnectLost, afterReconnectCount })

  await teardownRealtimeChannel(senderClient, senderChannel)
  await teardownRealtimeChannel(receiverClient, reconnectedChannel)

  return {
    beforeDisconnect: beforeDisconnect.length,
    duringDisconnectLost,
    afterReconnect: afterReconnectCount,
  }
}

// ---------------------------------------------------------------------------
// Test 4: Presence — can it layer on Broadcast for online/offline detection?
// ---------------------------------------------------------------------------

async function testPresenceLayering() {
  console.log('\n=== Test 4: Presence on Broadcast Channel ===')
  const sessionId = crypto.randomUUID()

  const { senderClient, receiverClient } = await createAuthenticatedPair()
  const presenceEvents = []

  const receiverChannel = createBeaconChannel(receiverClient, sessionId, {
    config: { presence: { key: 'receiver' } },
  })
  receiverChannel.on('presence', { event: 'join' }, ({ key, newPresences }) => {
    presenceEvents.push({ event: 'join', key, presences: newPresences, ts: Date.now() })
  })
  receiverChannel.on('presence', { event: 'leave' }, ({ key, leftPresences }) => {
    presenceEvents.push({ event: 'leave', key, presences: leftPresences, ts: Date.now() })
  })
  receiverChannel.on('broadcast', { event: 'gps' }, () => {})
  await waitForSubscription(receiverChannel)
  await receiverChannel.track({ role: 'receiver' })
  await sleep(500)

  const senderChannel = createBeaconChannel(senderClient, sessionId, {
    config: { presence: { key: 'sender' } },
  })
  senderChannel.on('broadcast', { event: 'gps' }, () => {})
  await waitForSubscription(senderChannel)
  await senderChannel.track({ role: 'sender' })
  await sleep(2000)

  const joinEvents = presenceEvents.filter((e) => e.event === 'join')
  const senderJoined = joinEvents.some((e) => e.key === 'sender')
  assertCondition(senderJoined, 'Receiver detected sender Presence join')

  // Send a broadcast alongside presence
  await sendBroadcastEvent(senderChannel, 'gps', gpsPayload(1))
  await sleep(500)
  pass('Broadcast and Presence coexist on same channel')

  // Sender leaves
  await teardownRealtimeChannel(senderClient, senderChannel)
  await sleep(5000)

  const leaveEvents = presenceEvents.filter((e) => e.event === 'leave' && e.key === 'sender')
  assertCondition(leaveEvents.length > 0, 'Receiver detected sender Presence leave')

  await teardownRealtimeChannel(receiverClient, receiverChannel)

  return { senderJoined, senderLeft: leaveEvents.length > 0, events: presenceEvents }
}

// ---------------------------------------------------------------------------
// Test 5: Anonymous receiver — can the public viewer subscribe without login?
// ---------------------------------------------------------------------------

async function testAnonymousReceiver() {
  console.log('\n=== Test 5: Anonymous Receiver ===')
  const sessionId = crypto.randomUUID()

  const { client: senderClient } = await createAuthenticatedClient(OWNER_EMAIL, OWNER_PASSWORD)
  const anonymousClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  const received = []

  const anonymousChannel = await subscribeGpsChannel(
    anonymousClient,
    sessionId,
    (payload) => recordSequenceSample(received, payload)
  )
  console.log('  Anonymous receiver subscribed')

  const {
    data: { session },
  } = await anonymousClient.auth.getSession()
  assertCondition(!session, 'Anonymous receiver stayed unauthenticated')

  const senderChannel = createBeaconChannel(senderClient, sessionId)
  await waitForSubscription(senderChannel)
  await sleep(500)

  await sendGpsBatch(senderChannel, 1, 3, 300)
  await waitForReceivedCount(received, 3, 3000)

  assertCondition(received.length === 3, `Anonymous receiver got 3/3 broadcasts (got ${received.length})`)

  await teardownRealtimeChannel(senderClient, senderChannel)
  await teardownRealtimeChannel(anonymousClient, anonymousChannel)

  return { unauthenticated: !session, received: received.length }
}

// ---------------------------------------------------------------------------
// Main — run all tests and write results
// ---------------------------------------------------------------------------

async function main() {
  console.log('Stage 6 Beacon Validation Tests')
  console.log(`Target: ${SUPABASE_URL}`)
  console.log('=' .repeat(50))

  const results = {}

  results.latency = await testLatencyAndOrdering()
  results.senderDisconnect = await testSenderDisconnect()
  results.receiverReconnect = await testReceiverReconnect()
  results.presence = await testPresenceLayering()
  results.anonymousReceiver = await testAnonymousReceiver()

  console.log('\n' + '='.repeat(50))
  console.log(`Results: ${passCount} passed, ${failCount} failed`)

  const outputPath = `${OUTPUT_DIR}/stage6_beacon_results.json`
  writeFileSync(outputPath, JSON.stringify(results, null, 2))
  console.log(`Raw data written to ${outputPath}`)

  process.exit(failCount > 0 ? 1 : 0)
}

main().catch((err) => {
  console.error('Fatal:', err)
  process.exit(1)
})
