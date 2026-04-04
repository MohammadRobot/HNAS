import {getAppCheck} from 'firebase-admin/app-check';
import {HttpError, type RequestLike} from './authz';

export async function assertAppCheckIfConfigured(req: RequestLike): Promise<void> {
  if (!isAppCheckEnforced()) {
    return;
  }

  const token = readHeader(req.headers, 'x-firebase-appcheck');
  if (!token) {
    throw new HttpError(
        401,
        'failed-precondition',
        'Missing X-Firebase-AppCheck header.',
    );
  }

  try {
    await getAppCheck().verifyToken(token);
  } catch {
    throw new HttpError(
        401,
        'failed-precondition',
        'Invalid Firebase App Check token.',
    );
  }
}

function isAppCheckEnforced(): boolean {
  const value = process.env.HNAS_ENFORCE_APP_CHECK;
  if (!value) {
    return false;
  }
  return value.trim().toLowerCase() === 'true';
}

function readHeader(
    headers: RequestLike['headers'],
    targetName: string,
): string | null {
  if (!headers) {
    return null;
  }

  const exact = headers[targetName];
  if (typeof exact === 'string') {
    return exact;
  }
  if (Array.isArray(exact) && exact.length > 0 && typeof exact[0] === 'string') {
    return exact[0];
  }

  const headerKey = Object.keys(headers).find((name) => name.toLowerCase() === targetName);
  if (!headerKey) {
    return null;
  }

  const value = headers[headerKey];
  if (typeof value === 'string') {
    return value;
  }
  if (Array.isArray(value) && value.length > 0 && typeof value[0] === 'string') {
    return value[0];
  }

  return null;
}
