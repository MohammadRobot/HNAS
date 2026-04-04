import express, {
  type NextFunction,
  type Request,
  type Response,
} from 'express';
import {type UserRecord, getAuth} from 'firebase-admin/auth';
import {FieldValue} from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';
import {
  assertPatientAccess,
  assertRole,
  getUserProfile,
  HttpError,
  parseFirebaseAuth,
  type AuthzUserProfile,
  type RequestLike,
} from '../lib/authz';
import {assertAppCheckIfConfigured} from '../lib/appCheck';
import {
  applySafetyFlags,
  computeRapidDose,
  type RapidDoseProfile,
} from '../lib/insulin';
import {assertRateLimit} from '../lib/rateLimit';
import {
  generateChecklistTasks,
  type ChecklistSourceRecord,
} from '../lib/checklistGenerator';
import {firestore, toDateId} from '../lib/firestore';
import {getDateIdForTimeZone, normalizeTimeZone} from '../lib/timezone';
import {type DailyChecklist, type Task} from '../lib/types';

type UnknownRecord = Record<string, unknown>;

interface AuthContext {
  uid: string;
  user: AuthzUserProfile;
}

interface AuthedRequest extends Request {
  authContext?: AuthContext;
}

interface MutableTaskResult {
  taskId: string;
  type: string;
  status?: string;
  completedAt?: string;
  note?: string;
  actualDoseAmount?: number;
  actualDoseUnit?: string;
  deliveredUnits?: number;
  glucoseMgDl?: number;
  mealTag?: string;
  inputs?: UnknownRecord;
  [key: string]: unknown;
}

const UPDATE_TASK_ALLOWED_STATUSES = new Set<string>([
  'pending',
  'completed',
  'done',
  'skipped',
  'failed',
  'missed',
  'late',
]);

const COMPLETION_LIKE_STATUSES = new Set<string>([
  'completed',
  'done',
  'skipped',
  'failed',
  'missed',
  'late',
]);

interface AiAskResponse {
  answer_text: string;
  answer_type: string;
  bullets: string[];
  disclaimer: string;
  references: string[];
  safety_flags: string[];
  next_actions: string[];
}

interface AiContextBundle {
  patientSummary: {
    patientId: string;
    fullName?: string;
    riskFlags: string[];
    diagnosis: string[];
  };
  taskContext?: {
    checklistDate: string;
    task: Task;
    result?: MutableTaskResult;
  };
  procedureTemplate?: UnknownRecord;
  insulinProfile?: RapidDoseProfile;
  references: string[];
}

interface FilterResult {
  blocked: boolean;
  reasons: string[];
}

interface ExternalModelConfig {
  provider: 'generic' | 'openai';
  endpoint: string;
  apiKey?: string;
  modelName: string;
}

const AI_RESPONSE_TYPES = new Set<string>([
  'general_guidance',
  'insulin_explanation',
  'insufficient_context',
  'safety_blocked',
]);

const DEFAULT_AI_DISCLAIMER = [
  'This assistant provides operational support only.',
  'It cannot diagnose, prescribe, or change treatment plans.',
].join(' ');

const DIAGNOSIS_PATTERNS: RegExp[] = [
  /\bdiagnos(?:e|is|ed|ing)\b/i,
  /\bwhat(?:'s| is)\s+wrong\b/i,
  /\bmedical\s+diagnosis\b/i,
];

const PRESCRIPTION_PATTERNS: RegExp[] = [
  /\bprescrib(?:e|ed|ing|er|ers|er's|ers')\b/i,
  /\bprescription\b/i,
  /\b(?:rx|medication)\s+(?:request|recommendation|order)\b/i,
];

const DOSE_CHANGE_PATTERNS: RegExp[] = [
  /\b(?:increase|decrease|adjust|change|raise|lower|titrate)\b.{0,24}\b(?:dose|insulin|units?)\b/i,
  /\b(?:change|adjust)\s+(?:my|the)\s+(?:insulin|medication)\b/i,
  /\b(?:should|can)\s+i\s+(?:increase|decrease|change)\b.{0,16}\b(?:dose|units?)\b/i,
];

const POST_FILTER_PATTERNS: RegExp[] = [
  /\byou\s+(?:should|must)\s+(?:increase|decrease|change|adjust)\b.{0,24}\b(?:dose|insulin|units?)\b/i,
  /\bi\s+diagnose\b/i,
  /\bi\s+prescribe\b/i,
];

const ALLOWED_PATIENT_GENDERS = new Set<string>([
  'male',
  'female',
  'other',
  'prefer_not_to_say',
]);

const ALLOWED_LAB_TEST_STATUSES = new Set<string>([
  'scheduled',
  'in_progress',
  'completed',
  'cancelled',
  'canceled',
]);

const ALLOWED_LAB_RESULT_FLAGS = new Set<string>([
  'normal',
  'low',
  'high',
  'critical',
  'abnormal',
]);

const REPORTS_COLLECTION = 'reports';
const REPORTS_DAILY_DOC_ID = 'daily';
const REPORTS_BY_DATE_SUBCOLLECTION = 'byDate';
const MANAGEABLE_USER_ROLES = new Set<string>([
  'admin',
  'supervisor',
  'nurse',
]);
const SUPERVISOR_MANAGEABLE_ROLES = new Set<string>([
  'nurse',
]);
const CHECKLIST_UPDATE_LIMIT_PER_MINUTE = readPositiveIntFromEnv(
    'HNAS_RATE_LIMIT_CHECKLIST_UPDATE_PER_MINUTE',
    90,
);
const AI_ASK_LIMIT_PER_MINUTE = readPositiveIntFromEnv(
    'HNAS_RATE_LIMIT_AI_ASK_PER_MINUTE',
    30,
);

const app = express();

app.use(express.json({limit: '1mb'}));
app.use('/api', (req, _res, next) => {
  void getAuthContext(req as AuthedRequest).then(() => next()).catch(next);
});
app.use('/api', (req, _res, next) => {
  void assertAppCheckIfConfigured(req as unknown as RequestLike)
      .then(() => next())
      .catch(next);
});

app.post('/api/dashboard/counts', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor', 'nurse']);

  const body = toOptionalBodyObject(req.body);
  const date = readOptionalString(body, 'date') ?? toDateId(new Date());
  assertDateId(date, 'date');

  let query: FirebaseFirestore.Query<FirebaseFirestore.DocumentData> =
    firestore.collection('patients');

  if (context.user.role === 'nurse') {
    query = query.where('assignedNurseIds', 'array-contains', context.uid);
  } else {
    query = query.where('agencyId', '==', requireUserAgencyId(context.user));
  }
  query = query.where('active', '==', true);

  const patientsSnapshot = await query.get();
  const reportRefs = patientsSnapshot.docs.map((patientDoc) => (
    patientDoc.ref
        .collection(REPORTS_COLLECTION)
        .doc(REPORTS_DAILY_DOC_ID)
        .collection(REPORTS_BY_DATE_SUBCOLLECTION)
        .doc(date)
  ));

  const reportSnapshots = reportRefs.length > 0 ?
    await firestore.getAll(...reportRefs) :
    [];

  let done = 0;
  let missed = 0;
  let late = 0;
  let skipped = 0;
  for (const reportSnap of reportSnapshots) {
    if (!reportSnap.exists) {
      continue;
    }

    const report = (reportSnap.data() ?? {}) as UnknownRecord;
    done += toNonNegativeInt(readRecordNumber(report, 'done'));
    missed += toNonNegativeInt(readRecordNumber(report, 'missed'));
    late += toNonNegativeInt(readRecordNumber(report, 'late'));
    skipped += toNonNegativeInt(readRecordNumber(report, 'skipped'));
  }

  res.status(200).json({
    ok: true,
    date,
    totalPatients: patientsSnapshot.size,
    done,
    missed,
    late,
    skipped,
  });
}));

app.post('/api/users/list', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor']);

  const body = toOptionalBodyObject(req.body);
  const requestedAgencyId = readOptionalString(body, 'agencyId');
  const targetAgencyId = resolveAgencyForWrite(context.user, requestedAgencyId);
  const roleFilter = readOptionalManagedUserRole(body, 'role');

  let query: FirebaseFirestore.Query<FirebaseFirestore.DocumentData> = firestore
      .collection('users')
      .where('agencyId', '==', targetAgencyId);
  if (roleFilter) {
    query = query.where('role', '==', roleFilter);
  }

  const snapshot = await query.get();
  const users = snapshot.docs.map((doc) => {
    const data = (doc.data() ?? {}) as UnknownRecord;
    return {
      uid: doc.id,
      role: readRecordString(data, 'role') ?? 'viewer',
      agencyId: readRecordString(data, 'agencyId') ?? '',
      displayName: readRecordString(data, 'displayName') ?? '',
      email: readRecordString(data, 'email') ?? '',
      updatedAt: readRecordString(data, 'updatedAt') ?? '',
      createdAt: readRecordString(data, 'createdAt') ?? '',
    };
  });

  const authUserByUid = await loadAuthUsersByUid(users.map((user) => user.uid));
  users.sort((left, right) => {
    const byName = left.displayName.localeCompare(right.displayName);
    if (byName !== 0) {
      return byName;
    }
    return left.email.localeCompare(right.email);
  });

  res.status(200).json({
    ok: true,
    users: users.map((user) => {
      const authUser = authUserByUid.get(user.uid);
      return {
        ...user,
        email: authUser?.email ?? user.email,
        disabled: authUser?.disabled ?? false,
        lastSignInAt: authUser?.metadata.lastSignInTime ?? null,
      };
    }),
  });
}));

app.post('/api/users/create', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor']);

  const body = requireBodyObject(req.body);
  const email = readRequiredString(body, 'email').toLowerCase();
  const password = readRequiredString(body, 'password');
  if (password.length < 8) {
    throw new HttpError(400, 'invalid-argument', 'password must be at least 8 characters.');
  }

  const displayName = readRequiredString(body, 'displayName');
  const role = readRequiredManagedUserRole(body, 'role');
  if (context.user.role === 'supervisor' && !SUPERVISOR_MANAGEABLE_ROLES.has(role)) {
    throw new HttpError(
        403,
        'permission-denied',
        'Supervisor can only create nurse users.',
    );
  }

  const requestedAgencyId = readOptionalString(body, 'agencyId');
  const agencyId = resolveAgencyForWrite(context.user, requestedAgencyId);
  const disabled = readOptionalBoolean(body, 'disabled') ?? false;
  const nowIso = new Date().toISOString();
  const auth = getAuth();

  let createdUser: UserRecord;
  try {
    createdUser = await auth.createUser({
      email,
      password,
      displayName,
      disabled,
    });
  } catch (error) {
    throw mapAuthErrorToHttp(error);
  }

  try {
    await firestore.collection('users').doc(createdUser.uid).set(
        {
          role,
          agencyId,
          displayName,
          email,
          createdAt: nowIso,
          updatedAt: nowIso,
        },
        {merge: true},
    );
  } catch (error) {
    try {
      await auth.deleteUser(createdUser.uid);
    } catch (rollbackError) {
      logger.error('Failed to rollback auth user after user profile write error.', {
        uid: createdUser.uid,
        rollbackError: rollbackError instanceof Error ?
          rollbackError.message :
          String(rollbackError),
      });
    }
    throw error;
  }

  res.status(201).json({
    ok: true,
    uid: createdUser.uid,
  });
}));

app.post('/api/users/update', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor']);

  const body = requireBodyObject(req.body);
  const uid = readRequiredString(body, 'uid');
  const userRef = firestore.collection('users').doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpError(404, 'not-found', `User "${uid}" was not found.`);
  }

  const existing = (userSnap.data() ?? {}) as UnknownRecord;
  const existingRole = readRecordString(existing, 'role') ?? 'viewer';
  const existingAgencyId = readRecordString(existing, 'agencyId') ?? '';

  if (context.user.role === 'supervisor') {
    const supervisorAgencyId = requireUserAgencyId(context.user);
    if (existingAgencyId !== supervisorAgencyId) {
      throw new HttpError(
          403,
          'permission-denied',
          'Supervisor can only manage users in their own agency.',
      );
    }
    if (!SUPERVISOR_MANAGEABLE_ROLES.has(existingRole)) {
      throw new HttpError(
          403,
          'permission-denied',
          'Supervisor can only manage nurse users.',
      );
    }
  }

  const profilePatch: UnknownRecord = {};
  const authPatch: {
    email?: string;
    password?: string;
    displayName?: string;
    disabled?: boolean;
  } = {};

  if (hasOwn(body, 'displayName')) {
    const displayName = readRequiredString(body, 'displayName');
    profilePatch.displayName = displayName;
    authPatch.displayName = displayName;
  }

  if (hasOwn(body, 'email')) {
    const email = readRequiredString(body, 'email').toLowerCase();
    profilePatch.email = email;
    authPatch.email = email;
  }

  if (hasOwn(body, 'password')) {
    const password = readRequiredString(body, 'password');
    if (password.length < 8) {
      throw new HttpError(400, 'invalid-argument', 'password must be at least 8 characters.');
    }
    authPatch.password = password;
  }

  if (hasOwn(body, 'disabled')) {
    authPatch.disabled = readRequiredBoolean(body, 'disabled');
  }

  if (hasOwn(body, 'role')) {
    if (uid === context.uid) {
      throw new HttpError(
          400,
          'invalid-argument',
          'Changing your own role is not allowed from this endpoint.',
      );
    }

    const role = readRequiredManagedUserRole(body, 'role');
    if (context.user.role === 'supervisor' && !SUPERVISOR_MANAGEABLE_ROLES.has(role)) {
      throw new HttpError(
          403,
          'permission-denied',
          'Supervisor can only assign nurse role.',
      );
    }
    profilePatch.role = role;
  }

  if (hasOwn(body, 'agencyId')) {
    const requestedAgencyId = readRequiredString(body, 'agencyId');
    profilePatch.agencyId = resolveAgencyForWrite(context.user, requestedAgencyId);
  }

  if (Object.keys(profilePatch).length === 0 && Object.keys(authPatch).length === 0) {
    throw new HttpError(400, 'invalid-argument', 'No updatable fields provided.');
  }

  if (Object.keys(authPatch).length > 0) {
    try {
      await getAuth().updateUser(uid, authPatch);
    } catch (error) {
      throw mapAuthErrorToHttp(error);
    }
  }

  if (Object.keys(profilePatch).length > 0) {
    profilePatch.updatedAt = new Date().toISOString();
    await userRef.set(profilePatch, {merge: true});
  }

  res.status(200).json({
    ok: true,
    uid,
  });
}));

app.post('/api/patients/list', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor', 'nurse']);

  const body = toOptionalBodyObject(req.body);
  const activeOnly = readOptionalBoolean(body, 'activeOnly') ?? true;

  let query: FirebaseFirestore.Query<FirebaseFirestore.DocumentData> =
    firestore.collection('patients');

  if (context.user.role === 'nurse') {
    query = query.where('assignedNurseIds', 'array-contains', context.uid);
  } else {
    query = query.where('agencyId', '==', requireUserAgencyId(context.user));
  }

  if (activeOnly) {
    query = query.where('active', '==', true);
  }

  const snapshot = await query.get();
  const patients = snapshot.docs.map((doc) => ({
    id: doc.id,
    ...(doc.data() as UnknownRecord),
  }));

  res.status(200).json({
    ok: true,
    patients,
  });
}));

app.post('/api/patients/create', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor']);

  const body = requireBodyObject(req.body);
  const fullName = readRequiredString(body, 'fullName');
  const timezone = readOptionalString(body, 'timezone') ?? 'Etc/UTC';
  const active = readOptionalBoolean(body, 'active') ?? true;
  const dateOfBirth = readOptionalString(body, 'dateOfBirth');
  if (dateOfBirth) {
    assertDateId(dateOfBirth, 'dateOfBirth');
  }
  const gender = readOptionalGender(body, 'gender');
  const phoneNumber = readOptionalString(body, 'phoneNumber');
  const emergencyContactName = readOptionalString(body, 'emergencyContactName');
  const emergencyContactPhone = readOptionalString(body, 'emergencyContactPhone');
  const address = readOptionalString(body, 'address');
  const notes = readOptionalString(body, 'notes');
  const riskFlags = readOptionalStringArray(body, 'riskFlags');
  const diagnosis = readOptionalStringArray(body, 'diagnosis');
  const allergies = readOptionalStringArray(body, 'allergies');
  const initialHealthCheckRaw = readOptionalObject(body, 'initialHealthCheck');
  const initialHealthCheck = initialHealthCheckRaw ?
    parseHealthCheckPayload(initialHealthCheckRaw, 'initialHealthCheck') :
    undefined;

  const requestedAgencyId = readOptionalString(body, 'agencyId');
  const agencyId = resolveAgencyForWrite(context.user, requestedAgencyId);
  const assignedNurseIds = readOptionalStringArray(body, 'assignedNurseIds') ?? [];
  const insulinProfiles = normalizeInsulinProfileArray(
      readOptionalArray(body, 'insulinProfiles') ?? [],
  );
  const nowIso = new Date().toISOString();

  const patientRef = firestore.collection('patients').doc();
  const patientData: UnknownRecord = {
    id: patientRef.id,
    fullName,
    timezone,
    active,
    agencyId,
    assignedNurseIds,
    createdAt: nowIso,
    updatedAt: nowIso,
  };

  if (dateOfBirth) {
    patientData.dateOfBirth = dateOfBirth;
  }
  if (gender) {
    patientData.gender = gender;
  }
  if (phoneNumber) {
    patientData.phoneNumber = phoneNumber;
  }
  if (emergencyContactName) {
    patientData.emergencyContactName = emergencyContactName;
  }
  if (emergencyContactPhone) {
    patientData.emergencyContactPhone = emergencyContactPhone;
  }
  if (address) {
    patientData.address = address;
  }
  if (notes) {
    patientData.notes = notes;
  }
  if (riskFlags && riskFlags.length > 0) {
    patientData.riskFlags = riskFlags;
  }
  if (diagnosis && diagnosis.length > 0) {
    patientData.diagnosis = diagnosis;
  }
  if (allergies && allergies.length > 0) {
    patientData.allergies = allergies;
  }

  await patientRef.set(patientData);
  await upsertInitialInsulinProfiles(patientRef, insulinProfiles, nowIso);
  if (initialHealthCheck) {
    await createHealthCheckRecord({
      patientRef,
      patientId: patientRef.id,
      actorUid: context.uid,
      payload: initialHealthCheck,
    });
  }

  res.status(201).json({
    ok: true,
    patientId: patientRef.id,
  });
}));

app.post('/api/patients/update', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  await assertPatientAccess(context.user, patientId);
  const insulinProfilesForUpsert = hasOwn(body, 'insulinProfiles') ?
    normalizeInsulinProfileArray(readRequiredArray(body, 'insulinProfiles')) :
    undefined;

  const patch: UnknownRecord = {};
  if (hasOwn(body, 'fullName')) {
    patch.fullName = readRequiredString(body, 'fullName');
  }
  if (hasOwn(body, 'timezone')) {
    patch.timezone = readRequiredString(body, 'timezone');
  }
  if (hasOwn(body, 'dateOfBirth')) {
    const dateOfBirth = readRequiredString(body, 'dateOfBirth');
    assertDateId(dateOfBirth, 'dateOfBirth');
    patch.dateOfBirth = dateOfBirth;
  }
  if (hasOwn(body, 'gender')) {
    patch.gender = readRequiredGender(body, 'gender');
  }
  if (hasOwn(body, 'phoneNumber')) {
    patch.phoneNumber = readRequiredString(body, 'phoneNumber');
  }
  if (hasOwn(body, 'emergencyContactName')) {
    patch.emergencyContactName = readRequiredString(body, 'emergencyContactName');
  }
  if (hasOwn(body, 'emergencyContactPhone')) {
    patch.emergencyContactPhone = readRequiredString(body, 'emergencyContactPhone');
  }
  if (hasOwn(body, 'address')) {
    patch.address = readRequiredString(body, 'address');
  }
  if (hasOwn(body, 'notes')) {
    patch.notes = readRequiredString(body, 'notes');
  }
  if (hasOwn(body, 'active')) {
    patch.active = readRequiredBoolean(body, 'active');
  }
  if (hasOwn(body, 'assignedNurseIds')) {
    patch.assignedNurseIds = readRequiredStringArray(body, 'assignedNurseIds');
  }
  if (hasOwn(body, 'riskFlags')) {
    patch.riskFlags = readRequiredStringArray(body, 'riskFlags');
  }
  if (hasOwn(body, 'diagnosis')) {
    patch.diagnosis = readRequiredStringArray(body, 'diagnosis');
  }
  if (hasOwn(body, 'allergies')) {
    patch.allergies = readRequiredStringArray(body, 'allergies');
  }
  if (hasOwn(body, 'agencyId')) {
    assertRole(context.user, ['admin']);
    patch.agencyId = readRequiredString(body, 'agencyId');
  }

  if (Object.keys(patch).length === 0) {
    throw new HttpError(400, 'invalid-argument', 'No updatable patient fields provided.');
  }

  const nowIso = new Date().toISOString();
  patch.updatedAt = nowIso;
  const patientRef = firestore.collection('patients').doc(patientId);
  await patientRef.set(patch, {merge: true});
  if (insulinProfilesForUpsert !== undefined) {
    await upsertInitialInsulinProfiles(patientRef, insulinProfilesForUpsert, nowIso);
    await patientRef.set({
      insulinProfiles: FieldValue.delete(),
      updatedAt: nowIso,
    }, {merge: true});
  }

  res.status(200).json({
    ok: true,
    patientId,
  });
}));

app.post('/api/patients/healthChecks/create', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor', 'nurse']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  await assertPatientAccess(context.user, patientId);

  const payload = parseHealthCheckPayload(body, 'body');
  const patientRef = firestore.collection('patients').doc(patientId);
  const healthCheckRef = await createHealthCheckRecord({
    patientRef,
    patientId,
    actorUid: context.uid,
    payload,
  });

  res.status(201).json({
    ok: true,
    patientId,
    healthCheckId: healthCheckRef.id,
  });
}));

app.post('/api/checklist/generate', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor', 'nurse']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  const requestedDate = readOptionalString(body, 'date');
  if (requestedDate) {
    assertDateId(requestedDate, 'date');
  }
  await assertPatientAccess(context.user, patientId);

  const patientRef = firestore.collection('patients').doc(patientId);
  const patientSnap = await patientRef.get();
  if (!patientSnap.exists) {
    throw new HttpError(404, 'not-found', `Patient "${patientId}" not found.`);
  }

  const patientData = (patientSnap.data() ?? {}) as UnknownRecord;
  const date = requestedDate ?? getDateIdForTimeZone(
      new Date(),
      normalizeTimeZone(patientData.timezone),
  );
  const [medicinesSnap, proceduresSnap, insulinSnap] = await Promise.all([
    patientRef.collection('medicines').where('active', '==', true).get(),
    patientRef.collection('procedures').where('active', '==', true).get(),
    patientRef.collection('insulinProfiles').where('active', '==', true).get(),
  ]);

  const medicines = medicinesSnap.docs.map(toChecklistSourceRecord);
  const procedures = proceduresSnap.docs.map(toChecklistSourceRecord);
  const insulinProfiles = resolveInsulinProfilesForChecklist(
      patientData,
      insulinSnap.docs.map(toChecklistSourceRecord),
  );
  const tasks = generateChecklistTasks({
    patientId,
    dateId: date,
    medicines,
    procedures,
    insulinProfiles,
  });

  const checklistRef = patientRef.collection('dailyChecklists').doc(date);
  const existingSnap = await checklistRef.get();
  const existing = existingSnap.exists ?
    (existingSnap.data() as Partial<DailyChecklist>) :
    undefined;
  const taskIds = new Set(tasks.map((task) => task.id));
  const existingResults = toMutableTaskResults(existing?.results)
      .filter((result) => taskIds.has(result.taskId));
  const existingIssuesRaw = existing?.issues;
  const existingIssues = Array.isArray(existingIssuesRaw) ? existingIssuesRaw : [];
  const nowIso = new Date().toISOString();
  const existingCreatedAt = existing?.createdAt;
  const createdAt = typeof existingCreatedAt === 'string' && existingCreatedAt.length > 0 ?
    existingCreatedAt :
    nowIso;

  const payload: UnknownRecord = {
    id: date,
    patientId,
    dateId: date,
    tasks,
    results: existingResults,
    issues: existingIssues,
    createdAt,
    updatedAt: nowIso,
  };

  await checklistRef.set(payload, {merge: false});

  res.status(200).json({
    ok: true,
    patientId,
    date,
    taskCount: tasks.length,
  });
}));

app.post('/api/medicines/create', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  await assertPatientAccess(context.user, patientId);

  const name = readRequiredString(body, 'name');
  const instructions = readOptionalString(body, 'instructions');
  const doseAmount = readOptionalNumber(body, 'doseAmount');
  const doseUnit = readOptionalString(body, 'doseUnit');
  const active = readOptionalBoolean(body, 'active') ?? true;
  const scheduleTimes = readOptionalTimeArray(body, 'scheduleTimes');
  const nowIso = new Date().toISOString();

  const medicineRef = firestore
      .collection('patients')
      .doc(patientId)
      .collection('medicines')
      .doc();
  const payload: UnknownRecord = {
    id: medicineRef.id,
    name,
    active,
    createdAt: nowIso,
    updatedAt: nowIso,
  };

  if (instructions) {
    payload.instructions = instructions;
  }
  if (doseAmount !== undefined) {
    payload.doseAmount = doseAmount;
  }
  if (doseUnit) {
    payload.doseUnit = doseUnit;
  }
  if (scheduleTimes && scheduleTimes.length > 0) {
    payload.scheduleTimes = scheduleTimes;
  }

  await medicineRef.set(payload);

  res.status(201).json({
    ok: true,
    medicineId: medicineRef.id,
  });
}));

app.post('/api/medicines/update', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  const medicineId = readRequiredString(body, 'medicineId');
  await assertPatientAccess(context.user, patientId);

  const medicineRef = firestore
      .collection('patients')
      .doc(patientId)
      .collection('medicines')
      .doc(medicineId);
  await assertDocumentExists(
      medicineRef,
      `Medicine "${medicineId}" for patient "${patientId}" was not found.`,
  );

  const patch: UnknownRecord = {};
  if (hasOwn(body, 'name')) {
    patch.name = readRequiredString(body, 'name');
  }
  if (hasOwn(body, 'instructions')) {
    patch.instructions = readRequiredString(body, 'instructions');
  }
  if (hasOwn(body, 'doseAmount')) {
    patch.doseAmount = readRequiredNumber(body, 'doseAmount');
  }
  if (hasOwn(body, 'doseUnit')) {
    patch.doseUnit = readRequiredString(body, 'doseUnit');
  }
  if (hasOwn(body, 'active')) {
    patch.active = readRequiredBoolean(body, 'active');
  }
  if (hasOwn(body, 'scheduleTimes')) {
    patch.scheduleTimes = readRequiredTimeArray(body, 'scheduleTimes');
  }

  if (Object.keys(patch).length === 0) {
    throw new HttpError(400, 'invalid-argument', 'No updatable medicine fields provided.');
  }

  patch.updatedAt = new Date().toISOString();
  await medicineRef.set(patch, {merge: true});

  res.status(200).json({
    ok: true,
    medicineId,
  });
}));

app.post('/api/procedures/create', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  await assertPatientAccess(context.user, patientId);

  const name = readRequiredString(body, 'name');
  const instructions = readOptionalString(body, 'instructions');
  const frequency = readOptionalString(body, 'frequency');
  const active = readOptionalBoolean(body, 'active') ?? true;
  const scheduleTimes = readOptionalTimeArray(body, 'scheduleTimes');
  const nowIso = new Date().toISOString();

  const procedureRef = firestore
      .collection('patients')
      .doc(patientId)
      .collection('procedures')
      .doc();
  const payload: UnknownRecord = {
    id: procedureRef.id,
    name,
    active,
    createdAt: nowIso,
    updatedAt: nowIso,
  };

  if (instructions) {
    payload.instructions = instructions;
  }
  if (frequency) {
    payload.frequency = frequency;
  }
  if (scheduleTimes && scheduleTimes.length > 0) {
    payload.scheduleTimes = scheduleTimes;
  }

  await procedureRef.set(payload);

  res.status(201).json({
    ok: true,
    procedureId: procedureRef.id,
  });
}));

app.post('/api/procedures/update', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  const procedureId = readRequiredString(body, 'procedureId');
  await assertPatientAccess(context.user, patientId);

  const procedureRef = firestore
      .collection('patients')
      .doc(patientId)
      .collection('procedures')
      .doc(procedureId);
  await assertDocumentExists(
      procedureRef,
      `Procedure "${procedureId}" for patient "${patientId}" was not found.`,
  );

  const patch: UnknownRecord = {};
  if (hasOwn(body, 'name')) {
    patch.name = readRequiredString(body, 'name');
  }
  if (hasOwn(body, 'instructions')) {
    patch.instructions = readRequiredString(body, 'instructions');
  }
  if (hasOwn(body, 'frequency')) {
    patch.frequency = readRequiredString(body, 'frequency');
  }
  if (hasOwn(body, 'active')) {
    patch.active = readRequiredBoolean(body, 'active');
  }
  if (hasOwn(body, 'scheduleTimes')) {
    patch.scheduleTimes = readRequiredTimeArray(body, 'scheduleTimes');
  }

  if (Object.keys(patch).length === 0) {
    throw new HttpError(400, 'invalid-argument', 'No updatable procedure fields provided.');
  }

  patch.updatedAt = new Date().toISOString();
  await procedureRef.set(patch, {merge: true});

  res.status(200).json({
    ok: true,
    procedureId,
  });
}));

app.post('/api/insulinProfiles/create', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  await assertPatientAccess(context.user, patientId);

  const type = readAndValidateInsulinType(body, 'type', 'rapid');
  const label = readRequiredString(body, 'label');
  const insulinName = readOptionalString(body, 'insulinName');
  const active = readOptionalBoolean(body, 'active') ?? true;
  const slidingScaleMgdl = readOptionalNumberArray(body, 'slidingScaleMgdl');
  const mealBaseUnits = readOptionalNumberMap(body, 'mealBaseUnits');
  const defaultBaseUnits = readOptionalNumber(body, 'defaultBaseUnits');
  const fixedUnits = readOptionalNumber(body, 'fixedUnits');
  const notes = readOptionalString(body, 'notes');
  const scheduleTimes = readOptionalTimeArray(body, 'scheduleTimes');
  const nowIso = new Date().toISOString();

  const profileRef = firestore
      .collection('patients')
      .doc(patientId)
      .collection('insulinProfiles')
      .doc();
  const payload: UnknownRecord = {
    id: profileRef.id,
    type,
    label,
    active,
    createdAt: nowIso,
    updatedAt: nowIso,
  };

  if (insulinName) {
    payload.insulinName = insulinName;
  }
  if (slidingScaleMgdl && slidingScaleMgdl.length > 0) {
    payload.slidingScaleMgdl = slidingScaleMgdl;
  }
  if (mealBaseUnits && Object.keys(mealBaseUnits).length > 0) {
    payload.mealBaseUnits = mealBaseUnits;
  }
  if (defaultBaseUnits !== undefined) {
    payload.defaultBaseUnits = defaultBaseUnits;
  }
  if (fixedUnits !== undefined) {
    payload.fixedUnits = fixedUnits;
  }
  if (notes) {
    payload.notes = notes;
  }
  if (scheduleTimes && scheduleTimes.length > 0) {
    payload.scheduleTimes = scheduleTimes;
  }

  await profileRef.set(payload);

  res.status(201).json({
    ok: true,
    insulinProfileId: profileRef.id,
  });
}));

app.post('/api/insulinProfiles/update', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  const insulinProfileId = readRequiredString(body, 'insulinProfileId');
  await assertPatientAccess(context.user, patientId);

  const profileRef = firestore
      .collection('patients')
      .doc(patientId)
      .collection('insulinProfiles')
      .doc(insulinProfileId);
  await assertDocumentExists(
      profileRef,
      `Insulin profile "${insulinProfileId}" for patient "${patientId}" was not found.`,
  );

  const patch: UnknownRecord = {};
  if (hasOwn(body, 'type')) {
    patch.type = readAndValidateInsulinType(body, 'type', undefined);
  }
  if (hasOwn(body, 'label')) {
    patch.label = readRequiredString(body, 'label');
  }
  if (hasOwn(body, 'insulinName')) {
    patch.insulinName = readRequiredString(body, 'insulinName');
  }
  if (hasOwn(body, 'active')) {
    patch.active = readRequiredBoolean(body, 'active');
  }
  if (hasOwn(body, 'slidingScaleMgdl')) {
    patch.slidingScaleMgdl = readRequiredNumberArray(body, 'slidingScaleMgdl');
  }
  if (hasOwn(body, 'mealBaseUnits')) {
    patch.mealBaseUnits = readRequiredNumberMap(body, 'mealBaseUnits');
  }
  if (hasOwn(body, 'defaultBaseUnits')) {
    patch.defaultBaseUnits = readRequiredNumber(body, 'defaultBaseUnits');
  }
  if (hasOwn(body, 'fixedUnits')) {
    patch.fixedUnits = readRequiredNumber(body, 'fixedUnits');
  }
  if (hasOwn(body, 'notes')) {
    patch.notes = readRequiredString(body, 'notes');
  }
  if (hasOwn(body, 'scheduleTimes')) {
    patch.scheduleTimes = readRequiredTimeArray(body, 'scheduleTimes');
  }

  if (Object.keys(patch).length === 0) {
    throw new HttpError(400, 'invalid-argument', 'No updatable insulin profile fields provided.');
  }

  patch.updatedAt = new Date().toISOString();
  await profileRef.set(patch, {merge: true});

  res.status(200).json({
    ok: true,
    insulinProfileId,
  });
}));

app.post('/api/labTests/create', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor', 'nurse']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  await assertPatientAccess(context.user, patientId);

  const testName = readRequiredString(body, 'testName');
  const panel = readOptionalString(body, 'panel');
  const scheduleDate = readOptionalString(body, 'scheduleDate');
  if (scheduleDate) {
    assertDateId(scheduleDate, 'scheduleDate');
  }
  const scheduleTimeRaw = readOptionalString(body, 'scheduleTime');
  const scheduleTime = scheduleTimeRaw ?
    normalizeClockTime(scheduleTimeRaw, 'scheduleTime') :
    undefined;
  const status = readAndValidateLabTestStatus(body, 'status', 'scheduled');
  const priority = readOptionalString(body, 'priority');
  const orderedBy = readOptionalString(body, 'orderedBy');
  const notes = readOptionalString(body, 'notes');
  const nowIso = new Date().toISOString();

  const labTestRef = firestore
      .collection('patients')
      .doc(patientId)
      .collection('labTests')
      .doc();
  const payload: UnknownRecord = {
    id: labTestRef.id,
    patientId,
    testName,
    status,
    createdAt: nowIso,
    updatedAt: nowIso,
  };

  if (panel) {
    payload.panel = panel;
  }
  if (scheduleDate) {
    payload.scheduleDate = scheduleDate;
  }
  if (scheduleTime) {
    payload.scheduleTime = scheduleTime;
  }
  if (priority) {
    payload.priority = priority;
  }
  if (orderedBy) {
    payload.orderedBy = orderedBy;
  }
  if (notes) {
    payload.notes = notes;
  }

  await labTestRef.set(payload);

  res.status(201).json({
    ok: true,
    labTestId: labTestRef.id,
  });
}));

app.post('/api/labTests/update', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor', 'nurse']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  const labTestId = readRequiredString(body, 'labTestId');
  await assertPatientAccess(context.user, patientId);

  const labTestRef = firestore
      .collection('patients')
      .doc(patientId)
      .collection('labTests')
      .doc(labTestId);
  await assertDocumentExists(
      labTestRef,
      `Lab test "${labTestId}" for patient "${patientId}" was not found.`,
  );

  const patch: UnknownRecord = {};
  if (hasOwn(body, 'testName')) {
    patch.testName = readRequiredString(body, 'testName');
  }
  if (hasOwn(body, 'panel')) {
    patch.panel = readRequiredString(body, 'panel');
  }
  if (hasOwn(body, 'scheduleDate')) {
    const scheduleDate = readRequiredString(body, 'scheduleDate');
    assertDateId(scheduleDate, 'scheduleDate');
    patch.scheduleDate = scheduleDate;
  }
  if (hasOwn(body, 'scheduleTime')) {
    const scheduleTime = normalizeClockTime(
        readRequiredString(body, 'scheduleTime'),
        'scheduleTime',
    );
    patch.scheduleTime = scheduleTime;
  }
  if (hasOwn(body, 'status')) {
    patch.status = readAndValidateLabTestStatus(body, 'status', undefined);
  }
  if (hasOwn(body, 'priority')) {
    patch.priority = readRequiredString(body, 'priority');
  }
  if (hasOwn(body, 'orderedBy')) {
    patch.orderedBy = readRequiredString(body, 'orderedBy');
  }
  if (hasOwn(body, 'notes')) {
    patch.notes = readRequiredString(body, 'notes');
  }

  if (Object.keys(patch).length === 0) {
    throw new HttpError(400, 'invalid-argument', 'No updatable lab test fields provided.');
  }

  patch.updatedAt = new Date().toISOString();
  await labTestRef.set(patch, {merge: true});

  res.status(200).json({
    ok: true,
    labTestId,
  });
}));

app.post('/api/labTests/result', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor', 'nurse']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  const labTestId = readRequiredString(body, 'labTestId');
  await assertPatientAccess(context.user, patientId);

  const resultValue = readRequiredString(body, 'resultValue');
  const resultUnit = readOptionalString(body, 'resultUnit');
  const referenceRange = readOptionalString(body, 'referenceRange');
  const interpretation = readOptionalString(body, 'interpretation');
  const resultFlag = readOptionalLabResultFlag(body, 'resultFlag');
  const resultAtRaw = readOptionalString(body, 'resultAt');
  const resultAt = parseIsoDateTimeOrThrow(resultAtRaw, 'resultAt');

  const labTestRef = firestore
      .collection('patients')
      .doc(patientId)
      .collection('labTests')
      .doc(labTestId);
  await assertDocumentExists(
      labTestRef,
      `Lab test "${labTestId}" for patient "${patientId}" was not found.`,
  );

  const nowIso = new Date().toISOString();
  const patch: UnknownRecord = {
    resultValue,
    resultAt,
    status: 'completed',
    updatedAt: nowIso,
  };

  if (resultUnit) {
    patch.resultUnit = resultUnit;
  }
  if (referenceRange) {
    patch.referenceRange = referenceRange;
  }
  if (interpretation) {
    patch.interpretation = interpretation;
  }
  if (resultFlag) {
    patch.resultFlag = resultFlag;
  }

  await labTestRef.set(patch, {merge: true});

  res.status(200).json({
    ok: true,
    labTestId,
  });
}));

app.post('/api/checklist/get', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  const body = requireBodyObject(req.body);

  const patientId = readRequiredString(body, 'patientId');
  const date = readRequiredString(body, 'date');
  assertDateId(date, 'date');

  await assertPatientAccess(context.user, patientId);

  const checklistRef = firestore
      .collection('patients')
      .doc(patientId)
      .collection('dailyChecklists')
      .doc(date);

  const snapshot = await checklistRef.get();
  if (!snapshot.exists) {
    throw new HttpError(
        404,
        'not-found',
        `Checklist "${date}" for patient "${patientId}" was not found.`,
    );
  }

  res.status(200).json({
    ok: true,
    checklist: {
      id: snapshot.id,
      ...(snapshot.data() as UnknownRecord),
    },
  });
}));

app.post('/api/checklist/updateTask', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  enforceRateLimitForUser(context.uid, 'checklist_update');
  const body = requireBodyObject(req.body);

  const patientId = readRequiredString(body, 'patientId');
  const date = readRequiredString(body, 'date');
  const taskId = readRequiredString(body, 'taskId');
  const status = readAndValidateStatus(body);
  const inputs = readOptionalObject(body, 'inputs') ?? {};

  assertDateId(date, 'date');
  await assertPatientAccess(context.user, patientId);

  const checklistRef = firestore
      .collection('patients')
      .doc(patientId)
      .collection('dailyChecklists')
      .doc(date);

  const updatedResult = await firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(checklistRef);
    if (!snapshot.exists) {
      throw new HttpError(
          404,
          'not-found',
          `Checklist "${date}" for patient "${patientId}" was not found.`,
      );
    }

    const checklist = snapshot.data() as Partial<DailyChecklist>;
    const tasks = toTaskList(checklist.tasks);
    const task = tasks.find((candidate) => candidate.id === taskId);
    if (!task) {
      throw new HttpError(404, 'not-found', `Task "${taskId}" not found in checklist "${date}".`);
    }

    const results = toMutableTaskResults(checklist.results);
    let result = results.find((candidate) => candidate.taskId === taskId);
    if (!result) {
      result = {
        taskId,
        type: task.type,
        status: 'pending',
      };
      results.push(result);
    }

    result.type = task.type;
    result.status = status;
    const nowIso = new Date().toISOString();

    if (COMPLETION_LIKE_STATUSES.has(status)) {
      if (typeof result.completedAt !== 'string' || result.completedAt.length === 0) {
        result.completedAt = nowIso;
      }
    } else if (status === 'pending') {
      delete result.completedAt;
    }

    applyTaskInputs(task, result, inputs);

    transaction.set(
        checklistRef,
        {
          results,
          updatedAt: nowIso,
        },
        {merge: true},
    );

    return {...result};
  });

  res.status(200).json({
    ok: true,
    result: updatedResult,
  });
}));

app.post('/api/reports/generate', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor', 'nurse']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  const startDate = readOptionalString(body, 'startDate');
  const endDate = readOptionalString(body, 'endDate');
  const maxDaysRaw = readOptionalNumber(body, 'maxDays') ?? 90;
  const maxDays = Math.trunc(maxDaysRaw);

  if (startDate) {
    assertDateId(startDate, 'startDate');
  }
  if (endDate) {
    assertDateId(endDate, 'endDate');
  }
  if (startDate && endDate && startDate > endDate) {
    throw new HttpError(400, 'invalid-argument', 'startDate cannot be after endDate.');
  }
  if (!Number.isFinite(maxDaysRaw) || maxDays < 1 || maxDays > 365) {
    throw new HttpError(400, 'invalid-argument', 'maxDays must be between 1 and 365.');
  }

  await assertPatientAccess(context.user, patientId);

  const patientRef = firestore.collection('patients').doc(patientId);
  let query: FirebaseFirestore.Query<FirebaseFirestore.DocumentData> = patientRef
      .collection('dailyChecklists')
      .orderBy('dateId', 'desc');
  if (startDate) {
    query = query.where('dateId', '>=', startDate);
  }
  if (endDate) {
    query = query.where('dateId', '<=', endDate);
  }

  const checklistSnapshot = await query.limit(maxDays).get();
  const nowIso = new Date().toISOString();
  const reportCollectionRef = patientRef
      .collection(REPORTS_COLLECTION)
      .doc(REPORTS_DAILY_DOC_ID)
      .collection(REPORTS_BY_DATE_SUBCOLLECTION);

  let batch = firestore.batch();
  let batchWrites = 0;
  let generatedCount = 0;
  let skippedCount = 0;
  let committedWrites = 0;
  const summaries: UnknownRecord[] = [];

  for (const checklistDoc of checklistSnapshot.docs) {
    const checklist = (checklistDoc.data() ?? {}) as UnknownRecord;
    const dateId = readRecordString(checklist, 'dateId') ?? checklistDoc.id;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateId)) {
      skippedCount += 1;
      continue;
    }

    const tasks = toTaskList(checklist.tasks);
    const results = toMutableTaskResults(checklist.results);
    const counts = aggregateDailyReportCounts(tasks, results);
    const reportPayload: UnknownRecord = {
      id: dateId,
      dateId,
      patientId,
      done: counts.done,
      missed: counts.missed,
      late: counts.late,
      skipped: counts.skipped,
      totalTasks: tasks.length,
      completedTasks: counts.done + counts.late + counts.skipped,
      sourceChecklistPath: checklistDoc.ref.path,
      createdAt: readRecordString(checklist, 'createdAt') ?? nowIso,
      updatedAt: nowIso,
    };

    batch.set(reportCollectionRef.doc(dateId), reportPayload, {merge: true});
    batchWrites += 1;
    generatedCount += 1;

    if (summaries.length < 31) {
      summaries.push({
        dateId,
        ...counts,
        totalTasks: tasks.length,
      });
    }

    if (batchWrites >= 400) {
      await batch.commit();
      committedWrites += batchWrites;
      batch = firestore.batch();
      batchWrites = 0;
    }
  }

  if (batchWrites > 0) {
    await batch.commit();
    committedWrites += batchWrites;
  }

  res.status(200).json({
    ok: true,
    patientId,
    startDate: startDate ?? null,
    endDate: endDate ?? null,
    sourceChecklistCount: checklistSnapshot.size,
    generatedCount,
    skippedCount,
    writesCommitted: committedWrites,
    summaries,
  });
}));

app.post('/api/ai/ask', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor', 'nurse']);
  enforceRateLimitForUser(context.uid, 'ai_ask');

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  const question = readRequiredString(body, 'question');
  const taskId = readOptionalString(body, 'taskId');
  const date = readOptionalString(body, 'date');
  const mealTag = readOptionalString(body, 'mealTag');
  const glucoseMgDl = readOptionalNumber(body, 'glucoseMgDl');
  const insulinProfileId = readOptionalString(body, 'insulinProfileId');

  if (date) {
    assertDateId(date, 'date');
  }

  await assertPatientAccess(context.user, patientId);

  const preFilter = runAiPreFilter(question);
  if (preFilter.blocked) {
    const blockedResponse = buildSafetyBlockedResponse(preFilter.reasons);
    await writeAiQaLog({
      patientId,
      actorUid: context.uid,
      model: 'guardrail-pre-filter',
      question,
      response: blockedResponse,
      taskId,
      checklistDateId: date,
      flagged: true,
    });
    res.status(200).json(blockedResponse);
    return;
  }

  let checklistDateForLog = date;
  try {
    const aiContext = await loadAiContext({
      patientId,
      taskId,
      date,
      insulinProfileId,
      includeInsulinContext: isInsulinDoseQuestion(question),
    });
    checklistDateForLog = aiContext.taskContext?.checklistDate ?? date;

    const fallbackResponse = buildTemplateAiResponse(question, aiContext);
    let finalResponse = fallbackResponse;
    let modelUsed = 'template-kb';

    if (isInsulinDoseQuestion(question)) {
      finalResponse = buildDeterministicInsulinResponse({
        question,
        aiContext,
        glucoseMgDl,
        mealTag,
      });
      modelUsed = 'deterministic-insulin';
    } else {
      const externalConfig = getExternalModelConfig();
      if (externalConfig) {
        const externalResponse = await tryExternalModelAnswer({
          config: externalConfig,
          question,
          aiContext,
          fallback: fallbackResponse,
        });

        if (externalResponse) {
          finalResponse = externalResponse;
          modelUsed = externalConfig.modelName;
        }
      }
    }

    const postFilter = runAiPostFilter(finalResponse.answer_text);
    if (postFilter.blocked) {
      finalResponse = buildSafetyBlockedResponse(postFilter.reasons);
      modelUsed = `${modelUsed}-post-filtered`;
    }

    finalResponse = enforceStrictAiResponse(finalResponse, fallbackResponse);

    await writeAiQaLog({
      patientId,
      actorUid: context.uid,
      model: modelUsed,
      question,
      response: finalResponse,
      taskId,
      checklistDateId: checklistDateForLog,
      flagged: postFilter.blocked || finalResponse.safety_flags.length > 0,
    });

    res.status(200).json(finalResponse);
  } catch (error) {
    const failureResponse = buildSafetyBlockedResponse(['processing_error']);

    try {
      await writeAiQaLog({
        patientId,
        actorUid: context.uid,
        model: 'ai-ask-error',
        question,
        response: failureResponse,
        taskId,
        checklistDateId: checklistDateForLog,
        flagged: true,
      });
    } catch (logError) {
      logger.error('Failed to write aiQaLogs error entry.', {
        patientId,
        error: logError instanceof Error ? logError.message : String(logError),
      });
    }

    throw error;
  }
}));

app.post('/api/ai/logs', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor', 'nurse']);

  const body = requireBodyObject(req.body);
  const patientId = readRequiredString(body, 'patientId');
  const requestedLimit = readOptionalNumber(body, 'limit');
  if (requestedLimit !== undefined && !Number.isInteger(requestedLimit)) {
    throw new HttpError(400, 'invalid-argument', 'limit must be an integer.');
  }
  const limit = requestedLimit === undefined ? 50 : requestedLimit;
  if (limit < 1 || limit > 200) {
    throw new HttpError(400, 'invalid-argument', 'limit must be between 1 and 200.');
  }

  await assertPatientAccess(context.user, patientId);

  const logsSnapshot = await firestore
      .collection('patients')
      .doc(patientId)
      .collection('aiQaLogs')
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .get();

  const logs = logsSnapshot.docs
      .map((doc) => {
        const data = (doc.data() ?? {}) as UnknownRecord;
        return {
          id: doc.id,
          prompt: readRecordString(data, 'prompt') ?? '',
          response: readRecordString(data, 'response') ?? '',
          answerType: readRecordString(data, 'answerType') ?? 'general_guidance',
          bullets: readRecordStringArray(data, 'bullets'),
          disclaimer: readRecordString(data, 'disclaimer') ?? '',
          references: readRecordStringArray(data, 'references'),
          safetyFlags: readRecordStringArray(data, 'safetyFlags'),
          nextActions: readRecordStringArray(data, 'nextActions'),
          model: readRecordString(data, 'model') ?? '',
          actorUid: readRecordString(data, 'actorUid') ?? '',
          createdAt: readRecordString(data, 'createdAt') ?? '',
          checklistDateId: readRecordString(data, 'checklistDateId'),
          taskId: readRecordString(data, 'taskId'),
          flagged: data.flagged === true,
        };
      })
      .reverse();

  res.status(200).json({
    ok: true,
    patientId,
    logs,
  });
}));

app.use((_req, res) => {
  res.status(404).json({
    ok: false,
    error: {
      code: 'not-found',
      message: 'Endpoint not found.',
    },
  });
});

app.use((error: unknown, req: Request, res: Response, next: NextFunction) => {
  void next;
  const normalized = normalizeError(error);
  if (normalized.statusCode >= 500) {
    const raw = describeUnknownError(error);
    logger.error('API request failed.', {
      code: normalized.code,
      statusCode: normalized.statusCode,
      responseMessage: normalized.message,
      requestMethod: req.method,
      requestPath: req.originalUrl || req.url,
      rawErrorName: raw.name,
      rawErrorMessage: raw.message,
      rawErrorStack: raw.stack,
    });
  }

  res.status(normalized.statusCode).json({
    ok: false,
    error: {
      code: normalized.code,
      message: normalized.message,
    },
  });
});

export default app;

type AsyncRoute = (req: AuthedRequest, res: Response) => Promise<void>;

function asyncRoute(handler: AsyncRoute) {
  return (req: Request, res: Response, next: NextFunction) => {
    void handler(req as AuthedRequest, res).catch(next);
  };
}

async function getAuthContext(req: AuthedRequest): Promise<AuthContext> {
  if (req.authContext) {
    return req.authContext;
  }

  const decoded = await parseFirebaseAuth(req as unknown as RequestLike);
  const user = await getUserProfile(decoded.uid);
  const context: AuthContext = {
    uid: decoded.uid,
    user,
  };

  req.authContext = context;
  return context;
}

function normalizeError(error: unknown): HttpError {
  if (error instanceof HttpError) {
    return error;
  }

  if (error instanceof SyntaxError) {
    return new HttpError(400, 'invalid-json', 'Malformed JSON request body.');
  }

  return new HttpError(500, 'internal', 'Unexpected server error.');
}

function describeUnknownError(error: unknown): {
  name: string;
  message: string;
  stack?: string;
} {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
      stack: error.stack,
    };
  }

  return {
    name: 'NonErrorThrow',
    message: String(error),
  };
}

function runAiPreFilter(question: string): FilterResult {
  const reasons: string[] = [];

  if (matchesAnyPattern(question, DIAGNOSIS_PATTERNS)) {
    reasons.push('diagnosis_request');
  }
  if (matchesAnyPattern(question, PRESCRIPTION_PATTERNS)) {
    reasons.push('prescription_request');
  }
  if (matchesAnyPattern(question, DOSE_CHANGE_PATTERNS)) {
    reasons.push('dose_change_request');
  }

  return {
    blocked: reasons.length > 0,
    reasons,
  };
}

function runAiPostFilter(answerText: string): FilterResult {
  const reasons: string[] = [];
  if (matchesAnyPattern(answerText, POST_FILTER_PATTERNS)) {
    reasons.push('forbidden_content_detected');
  }

  return {
    blocked: reasons.length > 0,
    reasons,
  };
}

function matchesAnyPattern(value: string, patterns: RegExp[]): boolean {
  return patterns.some((pattern) => pattern.test(value));
}

function buildSafetyBlockedResponse(reasons: string[]): AiAskResponse {
  const safetyReasons = reasons.length > 0 ? reasons : ['safety_blocked'];
  return {
    answer_text: [
      'I cannot help with diagnosis, prescribing, or changing doses.',
      'Please contact a licensed clinician for treatment decisions.',
    ].join(' '),
    answer_type: 'safety_blocked',
    bullets: [
      'Allowed scope: checklist guidance, documented procedures, and factual summaries.',
      'Clinical treatment decisions require a licensed clinician.',
    ],
    disclaimer: DEFAULT_AI_DISCLAIMER,
    references: [],
    safety_flags: safetyReasons,
    next_actions: [
      'Escalate to supervisor or clinician for medical advice.',
      'If urgent symptoms are present, follow emergency protocols.',
    ],
  };
}

interface LoadAiContextInput {
  patientId: string;
  taskId?: string;
  date?: string;
  insulinProfileId?: string;
  includeInsulinContext: boolean;
}

async function loadAiContext(input: LoadAiContextInput): Promise<AiContextBundle> {
  const patientRef = firestore.collection('patients').doc(input.patientId);
  const patientSnap = await patientRef.get();
  if (!patientSnap.exists) {
    throw new HttpError(404, 'not-found', `Patient "${input.patientId}" not found.`);
  }

  const patientData = (patientSnap.data() ?? {}) as UnknownRecord;
  const aiContext: AiContextBundle = {
    patientSummary: {
      patientId: input.patientId,
      fullName: readRecordString(patientData, 'fullName'),
      riskFlags: readRecordStringArray(patientData, 'riskFlags'),
      diagnosis: normalizeDiagnosis(patientData.diagnosis),
    },
    references: [patientRef.path],
  };

  if (input.taskId) {
    const checklistDate = input.date ?? getDateIdForTimeZone(
        new Date(),
        normalizeTimeZone(patientData.timezone),
    );
    const checklistRef = patientRef.collection('dailyChecklists').doc(checklistDate);
    const checklistSnap = await checklistRef.get();
    if (!checklistSnap.exists) {
      throw new HttpError(
          404,
          'not-found',
          `Checklist "${checklistDate}" for patient "${input.patientId}" was not found.`,
      );
    }

    const checklistData = checklistSnap.data() as Partial<DailyChecklist>;
    const tasks = toTaskList(checklistData.tasks);
    const task = tasks.find((candidate) => candidate.id === input.taskId);
    if (!task) {
      throw new HttpError(
          404,
          'not-found',
          `Task "${input.taskId}" not found in checklist "${checklistDate}".`,
      );
    }

    const result = toMutableTaskResults(checklistData.results)
        .find((candidate) => candidate.taskId === input.taskId);

    aiContext.taskContext = {
      checklistDate,
      task,
      result,
    };
    aiContext.references.push(checklistRef.path);

    if (task.type === 'procedure') {
      const template = await loadProcedureTemplate(task.procedureId);
      if (template) {
        aiContext.procedureTemplate = template.data;
        aiContext.references.push(template.reference);
      }
    }
  }

  const shouldLoadInsulin = input.includeInsulinContext ||
    Boolean(input.insulinProfileId) ||
    aiContext.taskContext?.task.type === 'insulin_rapid' ||
    aiContext.taskContext?.task.type === 'insulin_basal';

  if (shouldLoadInsulin) {
    let taskProfileId: string | undefined;
    const taskContextTask = aiContext.taskContext?.task;
    if (
      taskContextTask &&
      (taskContextTask.type === 'insulin_rapid' || taskContextTask.type === 'insulin_basal')
    ) {
      taskProfileId = taskContextTask.insulinProfileId;
    }

    const targetProfileId = input.insulinProfileId ?? taskProfileId;

    const insulinProfile = await loadRelevantInsulinProfile({
      patientRef,
      patientData,
      profileId: targetProfileId,
      preferRapid: input.includeInsulinContext,
    });

    if (insulinProfile) {
      aiContext.insulinProfile = insulinProfile.profile;
      if (insulinProfile.reference) {
        aiContext.references.push(insulinProfile.reference);
      }
    }
  }

  return aiContext;
}

async function loadProcedureTemplate(procedureId: string): Promise<{
  data: UnknownRecord;
  reference: string;
} | null> {
  const templateRef = firestore.collection('procedureTemplates').doc(procedureId);
  const templateSnap = await templateRef.get();
  if (!templateSnap.exists) {
    return null;
  }

  return {
    data: {
      id: templateSnap.id,
      ...(templateSnap.data() as UnknownRecord),
    },
    reference: templateRef.path,
  };
}

interface LoadInsulinProfileInput {
  patientRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  patientData: UnknownRecord;
  profileId?: string;
  preferRapid: boolean;
}

async function loadRelevantInsulinProfile(input: LoadInsulinProfileInput): Promise<{
  profile: RapidDoseProfile;
  reference?: string;
} | null> {
  if (input.profileId) {
    const resolved = await loadInsulinProfileById(input.patientRef, input.patientData, input.profileId);
    if (resolved) {
      return resolved;
    }
  }

  if (!input.preferRapid) {
    return null;
  }

  const profilesSnapshot = await input.patientRef.collection('insulinProfiles').get();
  const rapidDoc = profilesSnapshot.docs.find((doc) => {
    const data = doc.data();
    return data.type === 'rapid' && data.active !== false;
  });
  if (rapidDoc) {
    return {
      profile: {
        id: rapidDoc.id,
        ...(rapidDoc.data() as UnknownRecord),
      } as RapidDoseProfile,
      reference: rapidDoc.ref.path,
    };
  }

  const inlineProfiles = readRecordArray(input.patientData, 'insulinProfiles');
  const inlineRapid = inlineProfiles.find((candidate) => (
    candidate.type === 'rapid' && candidate.active !== false
  ));
  if (!inlineRapid) {
    return null;
  }

  const id = readRecordString(inlineRapid, 'id');
  if (!id) {
    return null;
  }

  return {
    profile: {
      id,
      ...(inlineRapid as UnknownRecord),
    } as RapidDoseProfile,
    reference: `${input.patientRef.path}/insulinProfiles/${id}`,
  };
}

async function loadInsulinProfileById(
    patientRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>,
    patientData: UnknownRecord,
    profileId: string,
): Promise<{
  profile: RapidDoseProfile;
  reference?: string;
} | null> {
  const profileRef = patientRef.collection('insulinProfiles').doc(profileId);
  const profileSnap = await profileRef.get();
  if (profileSnap.exists) {
    return {
      profile: {
        id: profileSnap.id,
        ...(profileSnap.data() as UnknownRecord),
      } as RapidDoseProfile,
      reference: profileRef.path,
    };
  }

  const inlineProfiles = readRecordArray(patientData, 'insulinProfiles');
  const inlineProfile = inlineProfiles.find((candidate) => candidate.id === profileId);
  if (!inlineProfile) {
    return null;
  }

  return {
    profile: {
      id: profileId,
      ...(inlineProfile as UnknownRecord),
    } as RapidDoseProfile,
    reference: `${patientRef.path}/insulinProfiles/${profileId}`,
  };
}

function buildTemplateAiResponse(question: string, aiContext: AiContextBundle): AiAskResponse {
  const bullets: string[] = [];
  const nextActions: string[] = [];

  if (aiContext.patientSummary.riskFlags.length > 0) {
    bullets.push(`Risk flags: ${aiContext.patientSummary.riskFlags.join(', ')}`);
  }
  if (aiContext.patientSummary.diagnosis.length > 0) {
    bullets.push(`Documented diagnosis context: ${aiContext.patientSummary.diagnosis.join(', ')}`);
  }

  if (aiContext.taskContext) {
    const task = aiContext.taskContext.task;
    bullets.push(
        `Task context: ${task.title} (${task.type}) on ${aiContext.taskContext.checklistDate}.`,
    );
    if (task.scheduledTime) {
      bullets.push(`Scheduled time: ${task.scheduledTime}.`);
    }
  }

  if (aiContext.procedureTemplate) {
    const templateName = readRecordString(aiContext.procedureTemplate, 'name') ??
      readRecordString(aiContext.procedureTemplate, 'title') ??
      'procedure template';
    bullets.push(`Procedure template available: ${templateName}.`);
  }

  if (aiContext.insulinProfile) {
    const profileName = aiContext.insulinProfile.label || aiContext.insulinProfile.insulinName;
    bullets.push(`Relevant insulin profile: ${profileName} (${aiContext.insulinProfile.type}).`);
  }

  if (bullets.length === 0) {
    bullets.push('Limited structured context is available for this question.');
  }

  nextActions.push('Review checklist/task context in the patient timeline.');
  if (aiContext.procedureTemplate) {
    nextActions.push('Follow the linked procedure template steps.');
  }
  nextActions.push('Escalate to clinician for diagnosis, prescribing, or dose changes.');

  return {
    answer_text: [
      'Here is a context-based operational summary from available records.',
      'I can help with documented workflow details but not clinical treatment decisions.',
      `Question received: "${question}".`,
    ].join(' '),
    answer_type: 'general_guidance',
    bullets,
    disclaimer: DEFAULT_AI_DISCLAIMER,
    references: uniqueStrings(aiContext.references),
    safety_flags: [],
    next_actions: uniqueStrings(nextActions),
  };
}

interface BuildInsulinResponseInput {
  question: string;
  aiContext: AiContextBundle;
  glucoseMgDl?: number;
  mealTag?: string;
}

function buildDeterministicInsulinResponse(input: BuildInsulinResponseInput): AiAskResponse {
  const profile = input.aiContext.insulinProfile;
  if (!profile || profile.type !== 'rapid') {
    return enforceStrictAiResponse(
        {
          answer_text: [
            'I could not compute a deterministic insulin dose explanation.',
            'A rapid insulin profile was not found in available context.',
          ].join(' '),
          answer_type: 'insufficient_context',
          bullets: [
            'Provide insulinProfileId for a rapid profile.',
            'Include glucoseMgDl and optional mealTag for deterministic calculations.',
          ],
          disclaimer: DEFAULT_AI_DISCLAIMER,
          references: input.aiContext.references,
          safety_flags: ['missing_rapid_profile'],
          next_actions: [
            'Re-send request with patientId, rapid insulin profile, and glucoseMgDl.',
            'Escalate to clinician for treatment decisions.',
          ],
        },
        buildTemplateAiResponse(input.question, input.aiContext),
    );
  }

  const glucose = firstFiniteNumber(
      input.glucoseMgDl,
      input.aiContext.taskContext?.result?.glucoseMgDl,
      readRecordNumber(
          asOptionalRecord(input.aiContext.taskContext?.result?.inputs),
          'glucoseMgDl',
      ),
  );

  if (!Number.isFinite(glucose)) {
    return enforceStrictAiResponse(
        {
          answer_text: [
            'I could not compute a deterministic insulin dose explanation.',
            'A glucose value is required for sliding scale calculations.',
          ].join(' '),
          answer_type: 'insufficient_context',
          bullets: [
            'Provide glucoseMgDl in the request or task inputs.',
            'Optional: include mealTag to apply meal base units.',
          ],
          disclaimer: DEFAULT_AI_DISCLAIMER,
          references: input.aiContext.references,
          safety_flags: ['missing_glucose'],
          next_actions: [
            'Capture current glucose and resend the request.',
            'Escalate to clinician for treatment decisions.',
          ],
        },
        buildTemplateAiResponse(input.question, input.aiContext),
    );
  }

  const effectiveMealTag = input.mealTag ??
    readRecordString(asOptionalRecord(input.aiContext.taskContext?.result?.inputs), 'mealTag') ??
    input.aiContext.taskContext?.result?.mealTag ??
    'none';

  const dose = computeRapidDose(effectiveMealTag, glucose, profile);
  const glucoseFlags = applySafetyFlags(glucose);
  const safetyFlags: string[] = [];
  if (glucoseFlags.low) {
    safetyFlags.push('low_glucose');
  }
  if (glucoseFlags.high) {
    safetyFlags.push('high_glucose');
  }

  const profileName = profile.label || profile.insulinName;

  return enforceStrictAiResponse(
      {
        answer_text: [
          `Deterministic insulin explanation for profile "${profileName}":`,
          `base ${dose.base} + sliding ${dose.sliding} = total ${dose.total} units.`,
        ].join(' '),
        answer_type: 'insulin_explanation',
        bullets: [
          `Glucose: ${glucose} mg/dL`,
          `Meal tag: ${effectiveMealTag}`,
          `Base units: ${dose.base}`,
          `Sliding units: ${dose.sliding}`,
          `Total units: ${dose.total}`,
        ],
        disclaimer: DEFAULT_AI_DISCLAIMER,
        references: input.aiContext.references,
        safety_flags: safetyFlags,
        next_actions: buildInsulinNextActions(glucoseFlags),
      },
      buildTemplateAiResponse(input.question, input.aiContext),
  );
}

function buildInsulinNextActions(flags: {low: boolean; high: boolean}): string[] {
  const actions: string[] = [
    'Verify glucose entry and profile selection before acting.',
    'Do not change treatment plans without clinician direction.',
  ];

  if (flags.low) {
    actions.unshift('Follow low-glucose protocol and escalate immediately.');
  } else if (flags.high) {
    actions.unshift('Monitor for high-glucose symptoms and notify supervisor/clinician.');
  }

  return uniqueStrings(actions);
}

function isInsulinDoseQuestion(question: string): boolean {
  const normalized = question.toLowerCase();
  const insulinMentioned = /\binsulin\b/.test(normalized);
  const doseMentioned = /\b(dose|units?|sliding\s*scale|correction|bolus|how\s+much)\b/.test(normalized);
  return insulinMentioned && doseMentioned;
}

function getExternalModelConfig(): ExternalModelConfig | null {
  const providerHint = firstNonEmptyString(
      process.env.AI_MODEL_PROVIDER,
      process.env.EXTERNAL_MODEL_PROVIDER,
  )?.toLowerCase();

  const configuredEndpoint = firstNonEmptyString(
      process.env.AI_MODEL_ENDPOINT,
      process.env.EXTERNAL_MODEL_ENDPOINT,
  );
  const openAiApiKey = firstNonEmptyString(process.env.OPENAI_API_KEY);
  const openAiEndpoint = firstNonEmptyString(
      process.env.OPENAI_ENDPOINT,
      process.env.OPENAI_API_ENDPOINT,
  ) ?? 'https://api.openai.com/v1/chat/completions';
  const openAiModelName = firstNonEmptyString(
      process.env.OPENAI_MODEL,
      process.env.OPENAI_MODEL_NAME,
  );

  if (providerHint === 'openai' || (openAiApiKey && !configuredEndpoint)) {
    const apiKey = firstNonEmptyString(
        process.env.AI_MODEL_API_KEY,
        process.env.EXTERNAL_MODEL_API_KEY,
        openAiApiKey,
    );
    const modelName = firstNonEmptyString(
        process.env.AI_MODEL_NAME,
        process.env.EXTERNAL_MODEL_NAME,
        openAiModelName,
    ) ?? 'gpt-4o-mini';

    return {
      provider: 'openai',
      endpoint: configuredEndpoint ?? openAiEndpoint,
      apiKey,
      modelName,
    };
  }

  if (!configuredEndpoint) {
    return null;
  }

  const inferredProvider = providerHint === 'openai' ||
    configuredEndpoint.includes('api.openai.com') ? 'openai' : 'generic';

  const apiKey = firstNonEmptyString(
      process.env.AI_MODEL_API_KEY,
      process.env.EXTERNAL_MODEL_API_KEY,
      openAiApiKey,
  );
  const modelName = firstNonEmptyString(
      process.env.AI_MODEL_NAME,
      process.env.EXTERNAL_MODEL_NAME,
      openAiModelName,
  ) ?? (inferredProvider === 'openai' ? 'gpt-4o-mini' : 'external-model');

  return {
    provider: inferredProvider,
    endpoint: configuredEndpoint,
    apiKey,
    modelName,
  };
}

interface TryExternalModelInput {
  config: ExternalModelConfig;
  question: string;
  aiContext: AiContextBundle;
  fallback: AiAskResponse;
}

async function tryExternalModelAnswer(
    input: TryExternalModelInput,
): Promise<AiAskResponse | null> {
  if (input.config.provider === 'openai') {
    return tryOpenAiAnswer(input);
  }

  const payload = {
    model: input.config.modelName,
    question: input.question,
    context: input.aiContext,
    instructions: [
      'Return strict JSON only.',
      'Do not diagnose, prescribe, or change doses.',
      'Schema: {answer_text,answer_type,bullets,disclaimer,references,safety_flags,next_actions}.',
    ].join(' '),
  };

  const headers: Record<string, string> = {
    'content-type': 'application/json',
  };
  if (input.config.apiKey) {
    headers.authorization = `Bearer ${input.config.apiKey}`;
  }

  try {
    const response = await fetch(input.config.endpoint, {
      method: 'POST',
      headers,
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      logger.warn('External model call failed with non-2xx status.', {
        status: response.status,
      });
      return null;
    }

    const responseText = await response.text();
    const parsed = parseExternalModelPayload(responseText);
    return enforceStrictAiResponse(parsed, input.fallback);
  } catch (error) {
    logger.warn('External model call failed; falling back to template response.', {
      error: error instanceof Error ? error.message : String(error),
    });
    return null;
  }
}

async function tryOpenAiAnswer(
    input: TryExternalModelInput,
): Promise<AiAskResponse | null> {
  if (!input.config.apiKey) {
    logger.warn('OpenAI provider selected but API key is missing.');
    return null;
  }

  const payload = {
    model: input.config.modelName,
    response_format: {
      type: 'json_object',
    },
    messages: [
      {
        role: 'system',
        content: [
          'You are an operational assistant for home nursing workflows.',
          'Never diagnose, prescribe, or suggest changing doses.',
          'Return strict JSON only.',
          'Schema: {answer_text,answer_type,bullets,disclaimer,references,safety_flags,next_actions}.',
          'answer_type must be one of: general_guidance, insulin_explanation, insufficient_context, safety_blocked.',
        ].join(' '),
      },
      {
        role: 'user',
        content: [
          `Question: ${input.question}`,
          `Context JSON: ${JSON.stringify(input.aiContext)}`,
          'Return one JSON object and no markdown fences.',
        ].join('\n\n'),
      },
    ],
  };

  try {
    const response = await fetch(input.config.endpoint, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'authorization': `Bearer ${input.config.apiKey}`,
      },
      body: JSON.stringify(payload),
    });

    const responseText = await response.text();
    if (!response.ok) {
      logger.warn('OpenAI model call failed with non-2xx status.', {
        status: response.status,
        body: responseText.slice(0, 400),
      });
      return null;
    }

    const parsed = parseOpenAiPayload(responseText);
    return enforceStrictAiResponse(parsed, input.fallback);
  } catch (error) {
    logger.warn('OpenAI model call failed; falling back to template response.', {
      error: error instanceof Error ? error.message : String(error),
    });
    return null;
  }
}

function parseOpenAiPayload(responseText: string): unknown {
  const parsed = parseJsonSafe(responseText);
  if (!isRecord(parsed)) {
    return parseExternalModelPayload(responseText);
  }

  if (typeof parsed.output_text === 'string' && parsed.output_text.trim().length > 0) {
    const asJson = parseJsonSafe(parsed.output_text);
    return asJson ?? buildAnswerLikePayload(parsed.output_text);
  }

  const choices = parsed.choices;
  if (Array.isArray(choices)) {
    for (const choice of choices) {
      if (!isRecord(choice) || !isRecord(choice.message)) {
        continue;
      }

      const content = extractOpenAiMessageText(choice.message.content);
      if (!content) {
        continue;
      }

      const asJson = parseJsonSafe(content);
      return asJson ?? buildAnswerLikePayload(content);
    }
  }

  return unwrapModelPayload(parsed);
}

function extractOpenAiMessageText(content: unknown): string | null {
  if (typeof content === 'string' && content.trim().length > 0) {
    return content.trim();
  }

  if (!Array.isArray(content)) {
    return null;
  }

  const chunks: string[] = [];
  for (const part of content) {
    if (!isRecord(part)) {
      continue;
    }

    const direct = toTrimmedText(part.text) ?? toTrimmedText(part.content);
    if (direct) {
      chunks.push(direct);
      continue;
    }

    if (isRecord(part.text)) {
      const value = toTrimmedText(part.text.value);
      if (value) {
        chunks.push(value);
      }
    }
  }

  if (chunks.length === 0) {
    return null;
  }
  return chunks.join('\n');
}

function toTrimmedText(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function parseExternalModelPayload(responseText: string): unknown {
  const direct = parseJsonSafe(responseText);
  if (direct !== null) {
    return unwrapModelPayload(direct);
  }

  return buildAnswerLikePayload(responseText);
}

function buildAnswerLikePayload(answerText: string): UnknownRecord {
  return {
    answer_text: answerText.trim(),
    answer_type: 'general_guidance',
    bullets: [],
    disclaimer: DEFAULT_AI_DISCLAIMER,
    references: [],
    safety_flags: [],
    next_actions: [],
  };
}

function unwrapModelPayload(payload: unknown): unknown {
  if (!isRecord(payload)) {
    return payload;
  }

  if (isRecord(payload.output)) {
    return payload.output;
  }

  if (isRecord(payload.data)) {
    return payload.data;
  }

  if (typeof payload.content === 'string') {
    const parsedContent = parseJsonSafe(payload.content);
    return parsedContent ?? payload;
  }

  return payload;
}

function parseJsonSafe(value: string): unknown | null {
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

function enforceStrictAiResponse(candidate: unknown, fallback: AiAskResponse): AiAskResponse {
  if (!isRecord(candidate)) {
    return fallback;
  }

  const answerText = toSingleLineString(candidate.answer_text) ?? fallback.answer_text;
  const answerTypeRaw = toSingleLineString(candidate.answer_type) ?? fallback.answer_type;
  const answerType = AI_RESPONSE_TYPES.has(answerTypeRaw) ? answerTypeRaw : fallback.answer_type;
  const bullets = sanitizeStringArray(candidate.bullets, fallback.bullets, 8);
  const disclaimer = toSingleLineString(candidate.disclaimer) ?? fallback.disclaimer;
  const references = sanitizeStringArray(candidate.references, fallback.references, 12);
  const safetyFlags = sanitizeStringArray(candidate.safety_flags, fallback.safety_flags, 12);
  const nextActions = sanitizeStringArray(candidate.next_actions, fallback.next_actions, 8);

  return {
    answer_text: answerText,
    answer_type: answerType,
    bullets,
    disclaimer,
    references,
    safety_flags: safetyFlags,
    next_actions: nextActions,
  };
}

interface WriteAiLogInput {
  patientId: string;
  actorUid: string;
  model: string;
  question: string;
  response: AiAskResponse;
  taskId?: string;
  checklistDateId?: string;
  flagged: boolean;
}

async function writeAiQaLog(input: WriteAiLogInput): Promise<void> {
  const logRef = firestore
      .collection('patients')
      .doc(input.patientId)
      .collection('aiQaLogs')
      .doc();
  const nowIso = new Date().toISOString();

  const payload: UnknownRecord = {
    id: logRef.id,
    patientId: input.patientId,
    model: input.model,
    prompt: input.question,
    response: input.response.answer_text,
    flagged: input.flagged,
    createdAt: nowIso,
    actorUid: input.actorUid,
    answerType: input.response.answer_type,
    bullets: input.response.bullets,
    disclaimer: input.response.disclaimer,
    references: input.response.references,
    safetyFlags: input.response.safety_flags,
    nextActions: input.response.next_actions,
  };

  if (input.checklistDateId) {
    payload.checklistDateId = input.checklistDateId;
  }

  if (input.taskId) {
    payload.taskId = input.taskId;
  }

  await logRef.set(payload);
}

function toChecklistSourceRecord(
    snapshot: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>,
): ChecklistSourceRecord {
  return {
    id: snapshot.id,
    ...(snapshot.data() as UnknownRecord),
  };
}

function normalizeInsulinProfileArray(values: unknown[]): UnknownRecord[] {
  if (values.length === 0) {
    return [];
  }

  const normalizedById = new Map<string, UnknownRecord>();
  values.forEach((value, index) => {
    if (!isRecord(value)) {
      return;
    }

    const existingId = readRecordString(value, 'id');
    const id = existingId ?? `profile_${index + 1}`;
    const rawType = readRecordString(value, 'type')?.toLowerCase();
    if (rawType && rawType !== 'rapid' && rawType !== 'basal') {
      return;
    }

    const profile: UnknownRecord = {
      ...value,
      id,
      type: rawType ?? 'rapid',
    };
    if (typeof profile.active !== 'boolean') {
      profile.active = true;
    }

    normalizedById.set(id, profile);
  });

  return Array.from(normalizedById.values());
}

async function upsertInitialInsulinProfiles(
    patientRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>,
    insulinProfiles: UnknownRecord[],
    nowIso: string,
): Promise<void> {
  if (insulinProfiles.length === 0) {
    return;
  }

  const batch = firestore.batch();
  let writes = 0;
  for (const profile of insulinProfiles) {
    const profileId = readRecordString(profile, 'id');
    if (!profileId) {
      continue;
    }

    const profileRef = patientRef.collection('insulinProfiles').doc(profileId);
    const payload: UnknownRecord = {
      ...profile,
      id: profileId,
      updatedAt: nowIso,
      createdAt: readRecordString(profile, 'createdAt') ?? nowIso,
    };
    batch.set(profileRef, payload, {merge: true});
    writes += 1;
  }
  if (writes > 0) {
    await batch.commit();
  }
}

function resolveInsulinProfilesForChecklist(
    patientData: UnknownRecord,
    subcollectionProfiles: ChecklistSourceRecord[],
): ChecklistSourceRecord[] {
  const inlineProfiles = extractInlineInsulinProfilesForChecklist(patientData);
  if (subcollectionProfiles.length === 0) {
    return inlineProfiles;
  }

  const merged = new Map<string, ChecklistSourceRecord>();
  for (const profile of inlineProfiles) {
    merged.set(profile.id, profile);
  }
  for (const profile of subcollectionProfiles) {
    merged.set(profile.id, profile);
  }

  return Array.from(merged.values());
}

function extractInlineInsulinProfilesForChecklist(
    patientData: UnknownRecord,
): ChecklistSourceRecord[] {
  const rawProfiles = readRecordArray(patientData, 'insulinProfiles');
  if (rawProfiles.length === 0) {
    return [];
  }

  const profiles: ChecklistSourceRecord[] = [];
  rawProfiles.forEach((rawProfile, index) => {
    const active = typeof rawProfile.active !== 'boolean' || rawProfile.active;
    if (!active) {
      return;
    }

    const id = typeof rawProfile.id === 'string' && rawProfile.id.length > 0 ?
      rawProfile.id :
      `inline_${index + 1}`;
    profiles.push({
      id,
      ...rawProfile,
    });
  });
  return profiles;
}

function normalizeDiagnosis(value: unknown): string[] {
  if (typeof value === 'string' && value.trim().length > 0) {
    return [value.trim()];
  }

  if (Array.isArray(value)) {
    return value.filter((item): item is string => typeof item === 'string');
  }

  return [];
}

function readRecordString(record: UnknownRecord | undefined, key: string): string | undefined {
  if (!record) {
    return undefined;
  }

  const value = record[key];
  if (typeof value !== 'string' || value.trim().length === 0) {
    return undefined;
  }

  return value.trim();
}

function readRecordNumber(record: UnknownRecord | undefined, key: string): number | undefined {
  if (!record) {
    return undefined;
  }

  const value = record[key];
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

function toNonNegativeInt(value: number | undefined): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, Math.trunc(value as number));
}

function readRecordStringArray(record: UnknownRecord, key: string): string[] {
  const value = record[key];
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((item): item is string => typeof item === 'string');
}

function readRecordArray(record: UnknownRecord, key: string): UnknownRecord[] {
  const value = record[key];
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((item): item is UnknownRecord => isRecord(item));
}

function firstFiniteNumber(...values: Array<number | undefined>): number {
  for (const value of values) {
    if (typeof value === 'number' && Number.isFinite(value)) {
      return value;
    }
  }

  return Number.NaN;
}

function firstNonEmptyString(...values: Array<string | undefined>): string | undefined {
  for (const value of values) {
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }

  return undefined;
}

function toSingleLineString(value: unknown): string | undefined {
  if (typeof value !== 'string') {
    return undefined;
  }

  const normalized = value.replace(/\s+/g, ' ').trim();
  return normalized.length > 0 ? normalized : undefined;
}

function sanitizeStringArray(
    value: unknown,
    fallback: string[],
    maxItems: number,
): string[] {
  if (!Array.isArray(value)) {
    return uniqueStrings(fallback).slice(0, maxItems);
  }

  const cleaned = value
      .filter((item): item is string => typeof item === 'string')
      .map((item) => item.trim())
      .filter((item) => item.length > 0);

  return uniqueStrings(cleaned).slice(0, maxItems);
}

function uniqueStrings(values: string[]): string[] {
  return Array.from(new Set(values));
}

function enforceRateLimitForUser(
    uid: string,
    action: 'checklist_update' | 'ai_ask',
): void {
  if (action === 'checklist_update') {
    assertRateLimit({
      bucketKey: `${action}:${uid}`,
      limit: CHECKLIST_UPDATE_LIMIT_PER_MINUTE,
      windowMs: 60_000,
      message: 'Too many checklist updates. Please slow down and retry.',
    });
    return;
  }

  assertRateLimit({
    bucketKey: `${action}:${uid}`,
    limit: AI_ASK_LIMIT_PER_MINUTE,
    windowMs: 60_000,
    message: 'Too many AI requests. Please retry in a minute.',
  });
}

function readPositiveIntFromEnv(name: string, defaultValue: number): number {
  const raw = process.env[name];
  if (!raw) {
    return defaultValue;
  }

  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    return defaultValue;
  }

  return parsed;
}

function resolveAgencyForWrite(user: AuthzUserProfile, requestedAgencyId?: string): string {
  if (user.role === 'supervisor') {
    const supervisorAgencyId = requireUserAgencyId(user);
    if (requestedAgencyId && requestedAgencyId !== supervisorAgencyId) {
      throw new HttpError(
          403,
          'permission-denied',
          'Supervisor cannot create or update records outside their agency.',
      );
    }
    return supervisorAgencyId;
  }

  if (requestedAgencyId) {
    return requestedAgencyId;
  }

  if (typeof user.agencyId === 'string' && user.agencyId.length > 0) {
    return user.agencyId;
  }

  throw new HttpError(400, 'invalid-argument', 'agencyId is required.');
}

function requireUserAgencyId(user: AuthzUserProfile): string {
  if (typeof user.agencyId === 'string' && user.agencyId.length > 0) {
    return user.agencyId;
  }

  throw new HttpError(403, 'permission-denied', 'User profile is missing agencyId.');
}

function readAndValidateStatus(body: UnknownRecord): string {
  const status = readRequiredString(body, 'status').toLowerCase();
  if (!UPDATE_TASK_ALLOWED_STATUSES.has(status)) {
    throw new HttpError(
        400,
        'invalid-argument',
        `status must be one of: ${Array.from(UPDATE_TASK_ALLOWED_STATUSES).join(', ')}.`,
    );
  }
  return status;
}

function applyTaskInputs(task: Task, result: MutableTaskResult, inputs: UnknownRecord): void {
  const mergedInputs: UnknownRecord = {
    ...(isRecord(result.inputs) ? result.inputs : {}),
    ...inputs,
  };
  result.inputs = mergedInputs;

  if (hasOwn(inputs, 'note')) {
    result.note = readRequiredString(inputs, 'note');
  }

  if (task.type === 'medicine') {
    if (hasOwn(inputs, 'actualDoseAmount')) {
      result.actualDoseAmount = readRequiredNumber(inputs, 'actualDoseAmount');
    }
    if (hasOwn(inputs, 'actualDoseUnit')) {
      result.actualDoseUnit = readRequiredString(inputs, 'actualDoseUnit');
    }
    return;
  }

  if (task.type === 'insulin_rapid') {
    if (hasOwn(inputs, 'glucoseMgDl')) {
      result.glucoseMgDl = readRequiredNumber(inputs, 'glucoseMgDl');
    }
    if (hasOwn(inputs, 'mealTag')) {
      result.mealTag = readRequiredString(inputs, 'mealTag');
    }
    if (hasOwn(inputs, 'deliveredUnits')) {
      result.deliveredUnits = readRequiredNumber(inputs, 'deliveredUnits');
    }
    return;
  }

  if (task.type === 'insulin_basal' && hasOwn(inputs, 'deliveredUnits')) {
    result.deliveredUnits = readRequiredNumber(inputs, 'deliveredUnits');
  }
}

function assertDateId(value: string, fieldName: string): void {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new HttpError(400, 'invalid-argument', `${fieldName} must be in YYYY-MM-DD format.`);
  }
}

function toTaskList(value: unknown): Task[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((item): item is Task => {
    if (!isRecord(item)) {
      return false;
    }

    return typeof item.id === 'string' &&
      typeof item.type === 'string' &&
      typeof item.title === 'string';
  });
}

function toMutableTaskResults(value: unknown): MutableTaskResult[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const results: MutableTaskResult[] = [];
  for (const item of value) {
    if (!isRecord(item)) {
      continue;
    }
    if (typeof item.taskId !== 'string' || typeof item.type !== 'string') {
      continue;
    }
    results.push({...(item as UnknownRecord)} as MutableTaskResult);
  }

  return results;
}

interface DailyReportCounts {
  done: number;
  missed: number;
  late: number;
  skipped: number;
}

function aggregateDailyReportCounts(
    tasks: Task[],
    results: MutableTaskResult[],
): DailyReportCounts {
  const resultByTaskId = new Map<string, MutableTaskResult>();
  for (const result of results) {
    resultByTaskId.set(result.taskId, result);
  }

  const counts: DailyReportCounts = {
    done: 0,
    missed: 0,
    late: 0,
    skipped: 0,
  };

  for (const task of tasks) {
    const status = normalizeReportStatus(resultByTaskId.get(task.id)?.status);
    if (status === 'completed' || status === 'done') {
      counts.done += 1;
      continue;
    }
    if (status === 'late') {
      counts.late += 1;
      continue;
    }
    if (status === 'skipped') {
      counts.skipped += 1;
      continue;
    }
    counts.missed += 1;
  }

  return counts;
}

function normalizeReportStatus(value: unknown): string {
  if (typeof value !== 'string') {
    return 'pending';
  }

  const normalized = value.trim().toLowerCase();
  if (normalized.length === 0) {
    return 'pending';
  }
  return normalized;
}

function requireBodyObject(value: unknown): UnknownRecord {
  if (!isRecord(value)) {
    throw new HttpError(400, 'invalid-argument', 'Request body must be a JSON object.');
  }
  return value;
}

function toOptionalBodyObject(value: unknown): UnknownRecord {
  if (value === undefined || value === null) {
    return {};
  }
  return requireBodyObject(value);
}

function readOptionalObject(obj: UnknownRecord, key: string): UnknownRecord | undefined {
  const value = obj[key];
  if (value === undefined) {
    return undefined;
  }
  if (!isRecord(value)) {
    throw new HttpError(400, 'invalid-argument', `${key} must be an object.`);
  }
  return value;
}

async function assertDocumentExists(
    documentRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>,
    notFoundMessage: string,
): Promise<void> {
  const snapshot = await documentRef.get();
  if (!snapshot.exists) {
    throw new HttpError(404, 'not-found', notFoundMessage);
  }
}

function readRequiredArray(obj: UnknownRecord, key: string): unknown[] {
  const value = obj[key];
  if (!Array.isArray(value)) {
    throw new HttpError(400, 'invalid-argument', `${key} must be an array.`);
  }
  return value;
}

function readOptionalArray(obj: UnknownRecord, key: string): unknown[] | undefined {
  const value = obj[key];
  if (value === undefined) {
    return undefined;
  }
  return readRequiredArray(obj, key);
}

function readRequiredNumberArray(obj: UnknownRecord, key: string): number[] {
  const value = obj[key];
  if (!Array.isArray(value)) {
    throw new HttpError(400, 'invalid-argument', `${key} must be an array of numbers.`);
  }

  const numbers = value.filter((item): item is number => (
    typeof item === 'number' && Number.isFinite(item)
  ));
  if (numbers.length !== value.length) {
    throw new HttpError(400, 'invalid-argument', `${key} must contain only finite numbers.`);
  }
  return numbers;
}

function readOptionalNumberArray(obj: UnknownRecord, key: string): number[] | undefined {
  const value = obj[key];
  if (value === undefined) {
    return undefined;
  }
  return readRequiredNumberArray(obj, key);
}

function readRequiredNumberMap(obj: UnknownRecord, key: string): Record<string, number> {
  const value = obj[key];
  if (!isRecord(value)) {
    throw new HttpError(
        400,
        'invalid-argument',
        `${key} must be an object with numeric values.`,
    );
  }

  const result: Record<string, number> = {};
  for (const [entryKey, entryValue] of Object.entries(value)) {
    const normalizedKey = entryKey.trim();
    if (!normalizedKey) {
      continue;
    }
    if (typeof entryValue !== 'number' || !Number.isFinite(entryValue)) {
      throw new HttpError(
          400,
          'invalid-argument',
          `${key}.${normalizedKey} must be a finite number.`,
      );
    }
    result[normalizedKey] = entryValue;
  }

  return result;
}

function readOptionalNumberMap(
    obj: UnknownRecord,
    key: string,
): Record<string, number> | undefined {
  const value = obj[key];
  if (value === undefined) {
    return undefined;
  }
  return readRequiredNumberMap(obj, key);
}

function readRequiredStringArray(obj: UnknownRecord, key: string): string[] {
  const value = obj[key];
  if (!Array.isArray(value)) {
    throw new HttpError(400, 'invalid-argument', `${key} must be an array of strings.`);
  }

  const strings = value.filter((item): item is string => typeof item === 'string');
  if (strings.length !== value.length) {
    throw new HttpError(400, 'invalid-argument', `${key} must contain only strings.`);
  }

  return Array.from(new Set(strings));
}

function readOptionalStringArray(obj: UnknownRecord, key: string): string[] | undefined {
  const value = obj[key];
  if (value === undefined) {
    return undefined;
  }
  return readRequiredStringArray(obj, key);
}

function readRequiredTimeArray(obj: UnknownRecord, key: string): string[] {
  const times = readRequiredStringArray(obj, key);
  const normalized = times.map((time) => normalizeClockTime(time, key));
  return Array.from(new Set(normalized)).sort();
}

function readOptionalTimeArray(obj: UnknownRecord, key: string): string[] | undefined {
  const value = obj[key];
  if (value === undefined) {
    return undefined;
  }
  return readRequiredTimeArray(obj, key);
}

function normalizeClockTime(raw: string, key: string): string {
  const value = raw.trim();
  const match = /^(\d{1,2}):(\d{2})$/.exec(value);
  if (!match) {
    throw new HttpError(400, 'invalid-argument', `${key} entries must use HH:mm format.`);
  }

  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    throw new HttpError(400, 'invalid-argument', `${key} entries must be valid 24h times.`);
  }

  return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
}

function readAndValidateInsulinType(
    obj: UnknownRecord,
    key: string,
    defaultValue: string | undefined,
): string {
  const raw = hasOwn(obj, key) ? readRequiredString(obj, key) : defaultValue;
  if (!raw) {
    throw new HttpError(400, 'invalid-argument', `${key} is required.`);
  }

  const normalized = raw.toLowerCase();
  if (normalized !== 'rapid' && normalized !== 'basal') {
    throw new HttpError(400, 'invalid-argument', `${key} must be either "rapid" or "basal".`);
  }
  return normalized;
}

function readRequiredString(obj: UnknownRecord, key: string): string {
  const value = obj[key];
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpError(400, 'invalid-argument', `${key} must be a non-empty string.`);
  }
  return value.trim();
}

function readOptionalString(obj: UnknownRecord, key: string): string | undefined {
  const value = obj[key];
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpError(400, 'invalid-argument', `${key} must be a non-empty string.`);
  }

  return value.trim();
}

function readRequiredGender(obj: UnknownRecord, key: string): string {
  const value = readRequiredString(obj, key).toLowerCase();
  if (!ALLOWED_PATIENT_GENDERS.has(value)) {
    throw new HttpError(
        400,
        'invalid-argument',
        `${key} must be one of: ${Array.from(ALLOWED_PATIENT_GENDERS).join(', ')}.`,
    );
  }
  return value;
}

function readOptionalGender(obj: UnknownRecord, key: string): string | undefined {
  const value = obj[key];
  if (value === undefined) {
    return undefined;
  }
  return readRequiredGender(obj, key);
}

function readAndValidateLabTestStatus(
    obj: UnknownRecord,
    key: string,
    defaultValue: string | undefined,
): string {
  const raw = hasOwn(obj, key) ? readRequiredString(obj, key) : defaultValue;
  if (!raw) {
    throw new HttpError(400, 'invalid-argument', `${key} is required.`);
  }

  const normalized = raw.toLowerCase();
  if (!ALLOWED_LAB_TEST_STATUSES.has(normalized)) {
    throw new HttpError(
        400,
        'invalid-argument',
        `${key} must be one of: ${Array.from(ALLOWED_LAB_TEST_STATUSES).join(', ')}.`,
    );
  }
  return normalized === 'canceled' ? 'cancelled' : normalized;
}

function readRequiredManagedUserRole(obj: UnknownRecord, key: string): string {
  const value = readRequiredString(obj, key).toLowerCase();
  if (!MANAGEABLE_USER_ROLES.has(value)) {
    throw new HttpError(
        400,
        'invalid-argument',
        `${key} must be one of: ${Array.from(MANAGEABLE_USER_ROLES).join(', ')}.`,
    );
  }

  return value;
}

function readOptionalManagedUserRole(
    obj: UnknownRecord,
    key: string,
): string | undefined {
  const value = obj[key];
  if (value === undefined) {
    return undefined;
  }

  return readRequiredManagedUserRole(obj, key);
}

function readOptionalLabResultFlag(obj: UnknownRecord, key: string): string | undefined {
  const value = readOptionalString(obj, key);
  if (!value) {
    return undefined;
  }

  const normalized = value.toLowerCase();
  if (!ALLOWED_LAB_RESULT_FLAGS.has(normalized)) {
    throw new HttpError(
        400,
        'invalid-argument',
        `${key} must be one of: ${Array.from(ALLOWED_LAB_RESULT_FLAGS).join(', ')}.`,
    );
  }
  return normalized;
}

async function loadAuthUsersByUid(uids: string[]): Promise<Map<string, UserRecord>> {
  const uniqueUids = Array.from(new Set(uids.filter((uid) => uid.length > 0)));
  if (uniqueUids.length === 0) {
    return new Map<string, UserRecord>();
  }

  const auth = getAuth();
  const result = new Map<string, UserRecord>();
  for (const chunk of chunkValues(uniqueUids, 100)) {
    const usersResult = await auth.getUsers(chunk.map((uid) => ({uid})));
    usersResult.users.forEach((user) => {
      result.set(user.uid, user);
    });
  }

  return result;
}

function chunkValues<T>(values: T[], chunkSize: number): T[][] {
  const chunks: T[][] = [];
  for (let index = 0; index < values.length; index += chunkSize) {
    chunks.push(values.slice(index, index + chunkSize));
  }

  return chunks;
}

function mapAuthErrorToHttp(error: unknown): HttpError {
  const code = isRecord(error) && typeof error.code === 'string' ?
    error.code :
    '';
  const message = isRecord(error) && typeof error.message === 'string' ?
    error.message :
    'Authentication provider request failed.';

  if (code === 'auth/email-already-exists') {
    return new HttpError(409, 'already-exists', 'Email already exists.');
  }
  if (code === 'auth/invalid-password') {
    return new HttpError(400, 'invalid-argument', 'Password is invalid.');
  }
  if (code === 'auth/invalid-email') {
    return new HttpError(400, 'invalid-argument', 'Email is invalid.');
  }
  if (code === 'auth/user-not-found') {
    return new HttpError(404, 'not-found', 'Target auth user was not found.');
  }

  return new HttpError(500, 'internal', message);
}

function parseIsoDateTimeOrThrow(raw: string | undefined, fieldName: string): string {
  if (!raw) {
    return new Date().toISOString();
  }

  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    throw new HttpError(400, 'invalid-argument', `${fieldName} must be valid ISO datetime.`);
  }
  return parsed.toISOString();
}

function readRequiredBoolean(obj: UnknownRecord, key: string): boolean {
  const value = obj[key];
  if (typeof value !== 'boolean') {
    throw new HttpError(400, 'invalid-argument', `${key} must be a boolean.`);
  }
  return value;
}

function readOptionalBoolean(obj: UnknownRecord, key: string): boolean | undefined {
  const value = obj[key];
  if (value === undefined) {
    return undefined;
  }
  return readRequiredBoolean(obj, key);
}

function readOptionalNumber(obj: UnknownRecord, key: string): number | undefined {
  const value = obj[key];
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new HttpError(400, 'invalid-argument', `${key} must be a finite number.`);
  }

  return value;
}

function readRequiredNumber(obj: UnknownRecord, key: string): number {
  const value = obj[key];
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new HttpError(400, 'invalid-argument', `${key} must be a finite number.`);
  }
  return value;
}

function hasOwn(obj: UnknownRecord, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(obj, key);
}

function asOptionalRecord(value: unknown): UnknownRecord | undefined {
  return isRecord(value) ? value : undefined;
}

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

interface HealthCheckPayload {
  checkedAt: string;
  weightKg?: number;
  temperatureC?: number;
  bloodPressureSystolic?: number;
  bloodPressureDiastolic?: number;
  pulseBpm?: number;
  spo2Pct?: number;
  notes?: string;
}

function parseHealthCheckPayload(
    obj: UnknownRecord,
    rootFieldName: string,
): HealthCheckPayload {
  const checkedAtRaw = readOptionalString(obj, 'checkedAt');
  const checkedAtDate = checkedAtRaw ? new Date(checkedAtRaw) : new Date();
  if (Number.isNaN(checkedAtDate.getTime())) {
    throw new HttpError(
        400,
        'invalid-argument',
        `${rootFieldName}.checkedAt must be a valid ISO date-time string.`,
    );
  }

  const weightKg = readOptionalNumber(obj, 'weightKg');
  const temperatureC = readOptionalNumber(obj, 'temperatureC');
  const bloodPressureSystolic = readOptionalNumber(obj, 'bloodPressureSystolic');
  const bloodPressureDiastolic = readOptionalNumber(obj, 'bloodPressureDiastolic');
  const pulseBpm = readOptionalNumber(obj, 'pulseBpm');
  const spo2Pct = readOptionalNumber(obj, 'spo2Pct');
  const notes = readOptionalString(obj, 'notes');

  if (
    weightKg === undefined &&
    temperatureC === undefined &&
    bloodPressureSystolic === undefined &&
    bloodPressureDiastolic === undefined &&
    pulseBpm === undefined &&
    spo2Pct === undefined
  ) {
    throw new HttpError(
        400,
        'invalid-argument',
        `${rootFieldName} must include at least one measurement.`,
    );
  }

  if (weightKg !== undefined) {
    assertNumberRange(weightKg, `${rootFieldName}.weightKg`, 0.5, 500);
  }
  if (temperatureC !== undefined) {
    assertNumberRange(temperatureC, `${rootFieldName}.temperatureC`, 25, 45);
  }
  if (bloodPressureSystolic !== undefined) {
    assertNumberRange(
        bloodPressureSystolic,
        `${rootFieldName}.bloodPressureSystolic`,
        40,
        300,
    );
  }
  if (bloodPressureDiastolic !== undefined) {
    assertNumberRange(
        bloodPressureDiastolic,
        `${rootFieldName}.bloodPressureDiastolic`,
        30,
        200,
    );
  }
  if (
    bloodPressureSystolic !== undefined &&
    bloodPressureDiastolic !== undefined &&
    bloodPressureSystolic <= bloodPressureDiastolic
  ) {
    throw new HttpError(
        400,
        'invalid-argument',
        `${rootFieldName} blood pressure systolic must be greater than diastolic.`,
    );
  }
  if (pulseBpm !== undefined) {
    assertNumberRange(pulseBpm, `${rootFieldName}.pulseBpm`, 20, 250);
  }
  if (spo2Pct !== undefined) {
    assertNumberRange(spo2Pct, `${rootFieldName}.spo2Pct`, 40, 100);
  }

  return {
    checkedAt: checkedAtDate.toISOString(),
    weightKg,
    temperatureC,
    bloodPressureSystolic,
    bloodPressureDiastolic,
    pulseBpm,
    spo2Pct,
    notes,
  };
}

function assertNumberRange(value: number, fieldName: string, min: number, max: number): void {
  if (value < min || value > max) {
    throw new HttpError(
        400,
        'invalid-argument',
        `${fieldName} must be between ${min} and ${max}.`,
    );
  }
}

async function createHealthCheckRecord(input: {
  patientRef: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  patientId: string;
  actorUid: string;
  payload: HealthCheckPayload;
}): Promise<FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>> {
  await assertDocumentExists(input.patientRef, `Patient "${input.patientId}" not found.`);

  const nowIso = new Date().toISOString();
  const healthCheckRef = input.patientRef.collection('healthChecks').doc();
  const record: UnknownRecord = {
    id: healthCheckRef.id,
    patientId: input.patientId,
    checkedAt: input.payload.checkedAt,
    dateId: toDateId(input.payload.checkedAt),
    recordedByUid: input.actorUid,
    createdAt: nowIso,
    updatedAt: nowIso,
  };

  if (input.payload.weightKg !== undefined) {
    record.weightKg = input.payload.weightKg;
  }
  if (input.payload.temperatureC !== undefined) {
    record.temperatureC = input.payload.temperatureC;
  }
  if (input.payload.bloodPressureSystolic !== undefined) {
    record.bloodPressureSystolic = input.payload.bloodPressureSystolic;
  }
  if (input.payload.bloodPressureDiastolic !== undefined) {
    record.bloodPressureDiastolic = input.payload.bloodPressureDiastolic;
  }
  if (input.payload.pulseBpm !== undefined) {
    record.pulseBpm = input.payload.pulseBpm;
  }
  if (input.payload.spo2Pct !== undefined) {
    record.spo2Pct = input.payload.spo2Pct;
  }
  if (input.payload.notes) {
    record.notes = input.payload.notes;
  }

  await healthCheckRef.set(record);
  return healthCheckRef;
}
