import {getAuth, type DecodedIdToken} from 'firebase-admin/auth';
import {firestore} from './firestore';

type HeaderValue = string | string[] | undefined;

export interface RequestLike {
  headers?: Record<string, HeaderValue>;
}

export interface AuthzUserProfile {
  uid: string;
  role: string;
  agencyId?: string;
  [key: string]: unknown;
}

interface PatientAccessDoc {
  agencyId?: string;
  assignedNurseIds?: unknown;
}

export class HttpError extends Error {
  readonly statusCode: number;
  readonly code: string;

  constructor(statusCode: number, code: string, message: string) {
    super(message);
    this.name = 'HttpError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

export async function parseFirebaseAuth(req: RequestLike): Promise<DecodedIdToken> {
  const authorization = readHeader(req.headers, 'authorization');
  if (!authorization) {
    throw new HttpError(401, 'unauthenticated', 'Missing Authorization header.');
  }

  const match = /^Bearer\s+(.+)$/i.exec(authorization.trim());
  if (!match || !match[1]) {
    throw new HttpError(401, 'unauthenticated', 'Expected Authorization: Bearer <token>.');
  }

  try {
    return await getAuth().verifyIdToken(match[1]);
  } catch {
    throw new HttpError(401, 'unauthenticated', 'Invalid or expired Firebase ID token.');
  }
}

export async function getUserProfile(uid: string): Promise<AuthzUserProfile> {
  if (!uid) {
    throw new HttpError(400, 'invalid-argument', 'uid is required.');
  }

  const snapshot = await firestore.collection('users').doc(uid).get();
  if (!snapshot.exists) {
    throw new HttpError(404, 'not-found', `User profile not found for uid "${uid}".`);
  }

  const data = snapshot.data() ?? {};
  if (typeof data.role !== 'string' || data.role.length === 0) {
    throw new HttpError(500, 'internal', `User profile "${uid}" is missing a valid role.`);
  }

  const agencyId = typeof data.agencyId === 'string' ? data.agencyId : undefined;
  return {
    uid,
    ...data,
    agencyId,
  } as AuthzUserProfile;
}

export function assertRole(user: AuthzUserProfile, allowedRoles: readonly string[]): void {
  if (!allowedRoles.includes(user.role)) {
    throw new HttpError(
        403,
        'permission-denied',
        `Role "${user.role}" is not allowed. Required: ${allowedRoles.join(', ')}.`,
    );
  }
}

export async function assertPatientAccess(
    user: AuthzUserProfile,
    patientId: string,
): Promise<void> {
  if (!patientId) {
    throw new HttpError(400, 'invalid-argument', 'patientId is required.');
  }

  const snapshot = await firestore.collection('patients').doc(patientId).get();
  if (!snapshot.exists) {
    throw new HttpError(404, 'not-found', `Patient "${patientId}" not found.`);
  }

  const patient = (snapshot.data() ?? {}) as PatientAccessDoc;

  if (user.role === 'nurse') {
    const assignedNurseIds = toStringList(patient.assignedNurseIds);
    if (!assignedNurseIds.includes(user.uid)) {
      throw new HttpError(403, 'permission-denied', 'Nurse is not assigned to this patient.');
    }
    return;
  }

  if (user.role === 'supervisor' || user.role === 'admin') {
    if (typeof user.agencyId !== 'string' || user.agencyId.length === 0) {
      throw new HttpError(
          403,
          'permission-denied',
          'Supervisor/admin user profile is missing agencyId.',
      );
    }

    if (typeof patient.agencyId !== 'string' || patient.agencyId !== user.agencyId) {
      throw new HttpError(
          403,
          'permission-denied',
          'Supervisor/admin can only access patients in the same agency.',
      );
    }
    return;
  }

  throw new HttpError(403, 'permission-denied', `Role "${user.role}" cannot access patients.`);
}

function readHeader(
    headers: Record<string, HeaderValue> | undefined,
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

function toStringList(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((item): item is string => typeof item === 'string');
}

