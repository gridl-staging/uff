import test from 'node:test'
import assert from 'node:assert/strict'

import {
  teardownRealtimeChannel,
  formatReceiverGpsLogLine,
  formatAuthFailureMessage,
  parsePositiveInteger,
} from './stage6_beacon_config.js'

test('teardownRealtimeChannel removes channel before disconnecting realtime client', async () => {
  const callOrder = []
  const channel = { id: 'beacon:test-session' }
  const client = {
    async removeChannel(channelToRemove) {
      callOrder.push(`remove:${channelToRemove.id}`)
      return 'ok'
    },
    realtime: {
      disconnect() {
        callOrder.push('disconnect')
      },
    },
  }

  await teardownRealtimeChannel(client, channel)

  assert.deepEqual(callOrder, ['remove:beacon:test-session', 'disconnect'])
})

test('teardownRealtimeChannel disconnects even when removeChannel rejects', async () => {
  const callOrder = []
  const channel = { id: 'beacon:test-session' }
  const client = {
    async removeChannel(channelToRemove) {
      callOrder.push(`remove:${channelToRemove.id}`)
      throw new Error('unsubscribe exploded')
    },
    realtime: {
      disconnect() {
        callOrder.push('disconnect')
      },
    },
  }

  await assert.rejects(() => teardownRealtimeChannel(client, channel), /unsubscribe exploded/)
  assert.deepEqual(callOrder, ['remove:beacon:test-session', 'disconnect'])
})

test('teardownRealtimeChannel rejects non-ok removeChannel statuses', async () => {
  const channel = { id: 'beacon:test-session' }
  const client = {
    async removeChannel() {
      return 'timed out'
    },
    realtime: {
      disconnect() {},
    },
  }

  await assert.rejects(
    () => teardownRealtimeChannel(client, channel),
    /Channel teardown failed: timed out/
  )
})

test('formatReceiverGpsLogLine includes sender embedded timestamp and sequence', () => {
  const receiveTs = Date.parse('2026-03-14T19:15:30.000Z')
  const payload = {
    seq: 9,
    ts: Date.parse('2026-03-14T19:15:29.123Z'),
    lat: 37.7749,
    lon: -122.4194,
  }

  const line = formatReceiverGpsLogLine(payload, receiveTs)

  assert.match(line, /^\[2026-03-14T19:15:30\.000Z\] seq=9 /)
  assert.match(line, /senderTs=2026-03-14T19:15:29\.123Z/)
  assert.match(line, /latency=877ms/)
  assert.match(line, /lat=37\.774900 lon=-122\.419400$/)
})

test('formatAuthFailureMessage points to Stage 3 reprovisioning after db reset', () => {
  const message = formatAuthFailureMessage('rls-owner@test.local', 'Invalid login credentials')

  assert.match(message, /^Auth failed for rls-owner@test\.local: Invalid login credentials/)
  assert.match(message, /stage3_provision_test_principals\.sh/)
  assert.match(message, /supabase db reset --local/)
})

test('parsePositiveInteger returns default when env value is missing', () => {
  assert.equal(parsePositiveInteger(undefined, 'BEACON_TIMEOUT_MS', 120000), 120000)
})

test('parsePositiveInteger accepts explicit positive integers', () => {
  assert.equal(parsePositiveInteger('15', 'BEACON_MESSAGE_COUNT', 5), 15)
})

test('parsePositiveInteger rejects malformed numeric strings', () => {
  assert.throws(
    () => parsePositiveInteger('5000ms', 'BEACON_INTERVAL_MS', 5000),
    /BEACON_INTERVAL_MS must be a positive integer/
  )
})

test('parsePositiveInteger rejects decimal strings', () => {
  assert.throws(
    () => parsePositiveInteger('12.5', 'BEACON_INTERVAL_MS', 5000),
    /BEACON_INTERVAL_MS must be a positive integer/
  )
})

test('parsePositiveInteger rejects unsafe integers that would be rounded', () => {
  assert.throws(
    () => parsePositiveInteger('9007199254740993', 'BEACON_TIMEOUT_MS', 120000),
    /BEACON_TIMEOUT_MS must be a positive integer/
  )
})
