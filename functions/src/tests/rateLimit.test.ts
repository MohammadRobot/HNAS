import test from 'node:test';
import assert from 'node:assert/strict';
import {assertRateLimit} from '../lib/rateLimit';
import {HttpError} from '../lib/authz';

test('assertRateLimit throws when limit is exceeded in active window', () => {
  const key = `test-window-${Date.now()}-${Math.random()}`;

  assertRateLimit({
    bucketKey: key,
    limit: 2,
    windowMs: 5_000,
    message: 'limit reached',
  });
  assertRateLimit({
    bucketKey: key,
    limit: 2,
    windowMs: 5_000,
    message: 'limit reached',
  });

  assert.throws(
      () => assertRateLimit({
        bucketKey: key,
        limit: 2,
        windowMs: 5_000,
        message: 'limit reached',
      }),
      (error: unknown) => (
        error instanceof HttpError &&
        error.statusCode === 429 &&
        error.code === 'resource-exhausted'
      ),
  );
});

test('assertRateLimit bypasses invalid limiter configs', () => {
  const key = `test-invalid-${Date.now()}-${Math.random()}`;

  assert.doesNotThrow(() => {
    assertRateLimit({
      bucketKey: key,
      limit: 0,
      windowMs: 60_000,
      message: 'ignored',
    });
    assertRateLimit({
      bucketKey: key,
      limit: 10,
      windowMs: 0,
      message: 'ignored',
    });
  });
});
