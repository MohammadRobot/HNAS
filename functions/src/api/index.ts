import {onRequest} from 'firebase-functions/v2/https';
import app from './app';

export const api = onRequest(
    {
      cors: resolveCorsOrigins(),
    },
    app,
);

function resolveCorsOrigins(): true | string[] {
  const raw = process.env.HNAS_ALLOWED_ORIGINS;
  if (!raw) {
    return true;
  }

  const origins = raw
      .split(',')
      .map((item) => item.trim())
      .filter((item) => item.length > 0);
  if (origins.length === 0) {
    return true;
  }

  return origins;
}
