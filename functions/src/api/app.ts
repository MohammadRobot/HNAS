import express, {
  type NextFunction,
  type Request,
  type Response,
} from 'express';
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
import {
  applySafetyFlags,
  computeRapidDose,
  type RapidDoseProfile,
} from '../lib/insulin';
import {firestore, toDateId} from '../lib/firestore';
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

const app = express();

app.use(express.json({limit: '1mb'}));
app.use('/api', (req, _res, next) => {
  void getAuthContext(req as AuthedRequest).then(() => next()).catch(next);
});

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

  const requestedAgencyId = readOptionalString(body, 'agencyId');
  const agencyId = resolveAgencyForWrite(context.user, requestedAgencyId);
  const assignedNurseIds = readOptionalStringArray(body, 'assignedNurseIds') ?? [];
  const insulinProfiles = readOptionalArray(body, 'insulinProfiles') ?? [];
  const nowIso = new Date().toISOString();

  const patientRef = firestore.collection('patients').doc();
  const patientData: UnknownRecord = {
    id: patientRef.id,
    fullName,
    timezone,
    active,
    agencyId,
    assignedNurseIds,
    insulinProfiles,
    createdAt: nowIso,
    updatedAt: nowIso,
  };

  if (dateOfBirth) {
    patientData.dateOfBirth = dateOfBirth;
  }

  await patientRef.set(patientData);

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
  if (hasOwn(body, 'active')) {
    patch.active = readRequiredBoolean(body, 'active');
  }
  if (hasOwn(body, 'assignedNurseIds')) {
    patch.assignedNurseIds = readRequiredStringArray(body, 'assignedNurseIds');
  }
  if (hasOwn(body, 'insulinProfiles')) {
    patch.insulinProfiles = readRequiredArray(body, 'insulinProfiles');
  }
  if (hasOwn(body, 'agencyId')) {
    assertRole(context.user, ['admin']);
    patch.agencyId = readRequiredString(body, 'agencyId');
  }

  if (Object.keys(patch).length === 0) {
    throw new HttpError(400, 'invalid-argument', 'No updatable patient fields provided.');
  }

  patch.updatedAt = new Date().toISOString();
  await firestore.collection('patients').doc(patientId).set(patch, {merge: true});

  res.status(200).json({
    ok: true,
    patientId,
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

app.post('/api/ai/ask', asyncRoute(async (req, res) => {
  const context = await getAuthContext(req);
  assertRole(context.user, ['admin', 'supervisor', 'nurse']);

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

app.use((_req, res) => {
  res.status(404).json({
    ok: false,
    error: {
      code: 'not-found',
      message: 'Endpoint not found.',
    },
  });
});

app.use((error: unknown, _req: Request, res: Response, next: NextFunction) => {
  void next;
  const normalized = normalizeError(error);
  if (normalized.statusCode >= 500) {
    logger.error('API request failed.', {
      code: normalized.code,
      message: normalized.message,
      stack: normalized.stack,
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
    const checklistDate = input.date ?? toDateId(new Date());
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
  const endpoint = firstNonEmptyString(
      process.env.AI_MODEL_ENDPOINT,
      process.env.EXTERNAL_MODEL_ENDPOINT,
  );
  if (!endpoint) {
    return null;
  }

  const apiKey = firstNonEmptyString(
      process.env.AI_MODEL_API_KEY,
      process.env.EXTERNAL_MODEL_API_KEY,
  );
  const modelName = firstNonEmptyString(
      process.env.AI_MODEL_NAME,
      process.env.EXTERNAL_MODEL_NAME,
  ) ?? 'external-model';

  return {endpoint, apiKey, modelName};
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

function parseExternalModelPayload(responseText: string): unknown {
  const direct = parseJsonSafe(responseText);
  if (direct !== null) {
    return unwrapModelPayload(direct);
  }

  return {
    answer_text: responseText.trim(),
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
