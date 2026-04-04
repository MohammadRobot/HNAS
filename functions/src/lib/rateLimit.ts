import {HttpError} from './authz';

interface Bucket {
  count: number;
  resetAtMs: number;
}

interface RateLimitOptions {
  bucketKey: string;
  limit: number;
  windowMs: number;
  message: string;
}

const buckets = new Map<string, Bucket>();

export function assertRateLimit(options: RateLimitOptions): void {
  if (!Number.isFinite(options.limit) || options.limit <= 0) {
    return;
  }
  if (!Number.isFinite(options.windowMs) || options.windowMs <= 0) {
    return;
  }

  const now = Date.now();
  const bucket = buckets.get(options.bucketKey);
  if (!bucket || now >= bucket.resetAtMs) {
    buckets.set(options.bucketKey, {
      count: 1,
      resetAtMs: now + options.windowMs,
    });
    cleanupExpiredBuckets(now);
    return;
  }

  if (bucket.count >= options.limit) {
    throw new HttpError(429, 'resource-exhausted', options.message);
  }

  bucket.count += 1;
  cleanupExpiredBuckets(now);
}

function cleanupExpiredBuckets(now: number): void {
  // Keep the in-memory limiter bounded across warm invocations.
  if (buckets.size < 2000) {
    return;
  }

  for (const [key, bucket] of buckets.entries()) {
    if (bucket.resetAtMs <= now) {
      buckets.delete(key);
    }
  }
}
