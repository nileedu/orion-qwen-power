import assert from 'node:assert/strict'
import test from 'node:test'
import { calculateHeapUsagePercent } from '../core/watchdog.js'

test('heap pressure uses the V8 heap limit instead of the current allocated heap', () => {
  const used = 74 * 1024 * 1024
  const allocated = 76 * 1024 * 1024
  const limit = 4 * 1024 * 1024 * 1024

  assert.ok((used / allocated) * 100 > 95)
  assert.ok(calculateHeapUsagePercent(used, limit) < 2)
})

test('heap pressure preserves warning and critical percentages near the real limit', () => {
  const limit = 1000
  assert.equal(calculateHeapUsagePercent(800, limit), 80)
  assert.equal(calculateHeapUsagePercent(950, limit), 95)
  assert.equal(calculateHeapUsagePercent(1, 0), 100)
})
