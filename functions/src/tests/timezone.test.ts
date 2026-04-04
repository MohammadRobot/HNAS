import test from 'node:test';
import assert from 'node:assert/strict';
import {
  getDateIdForTimeZone,
  normalizeTimeZone,
  shouldGenerateChecklistNow,
  shouldRunEndOfDaySweepNow,
} from '../lib/timezone';

test('getDateIdForTimeZone resolves local date by time zone', () => {
  const date = new Date('2026-04-05T00:30:00.000Z');

  assert.equal(getDateIdForTimeZone(date, 'America/Los_Angeles'), '2026-04-04');
  assert.equal(getDateIdForTimeZone(date, 'Asia/Dubai'), '2026-04-05');
});

test('normalizeTimeZone falls back to UTC for invalid values', () => {
  assert.equal(normalizeTimeZone(undefined), 'Etc/UTC');
  assert.equal(normalizeTimeZone('Invalid/Zone'), 'Etc/UTC');
  assert.equal(normalizeTimeZone('Asia/Dubai'), 'Asia/Dubai');
});

test('shouldGenerateChecklistNow checks local midnight window', () => {
  const atMidnightDubai = new Date('2026-04-04T20:00:00.000Z');
  const outsideWindowDubai = new Date('2026-04-04T20:20:00.000Z');

  assert.equal(shouldGenerateChecklistNow(atMidnightDubai, 'Asia/Dubai'), true);
  assert.equal(shouldGenerateChecklistNow(outsideWindowDubai, 'Asia/Dubai'), false);
});

test('shouldRunEndOfDaySweepNow checks local late-evening window', () => {
  const inSweepWindowDubai = new Date('2026-04-05T19:46:00.000Z');
  const outsideSweepWindowDubai = new Date('2026-04-05T19:30:00.000Z');

  assert.equal(shouldRunEndOfDaySweepNow(inSweepWindowDubai, 'Asia/Dubai'), true);
  assert.equal(shouldRunEndOfDaySweepNow(outsideSweepWindowDubai, 'Asia/Dubai'), false);
});
