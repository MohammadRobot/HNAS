import * as logger from 'firebase-functions/logger';
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import {
  applySafetyFlags,
  computeRapidDose,
  type RapidDoseProfile,
} from '../lib/insulin';
import {
  checkLate,
  createIssue,
  validateRequiredInputs,
} from '../lib/rulesEngine';
import { firestore } from '../lib/firestore';
import { type DailyChecklist, type Issue, type Task } from '../lib/types';

const CHECKLIST_PATH = 'patients/{patientId}/dailyChecklists/{dateId}';
const TASK_LOGS_SUBCOLLECTION = 'taskLogs';
const ISSUES_SUBCOLLECTION = 'issues';
const INSULIN_PROFILES_SUBCOLLECTION = 'insulinProfiles';

type ResultStatus =
  | 'pending'
  | 'completed'
  | 'done'
  | 'skipped'
  | 'failed'
  | 'missed'
  | 'late'
  | 'unknown';

interface MutableTaskResult {
  taskId: string;
  type: string;
  status?: string;
  completedAt?: string;
  note?: string;
  glucoseMgDl?: number;
  deliveredUnits?: number;
  mealTag?: string;
  baseUnits?: number;
  slidingUnits?: number;
  totalUnits?: number;
  [key: string]: unknown;
}

interface TaskLogEntry {
  id: string;
  patientId: string;
  checklistDateId: string;
  taskId: string;
  taskType: string;
  status: 'completed' | 'late';
  event: 'task_completed';
  completedAt: string;
  missingInputs: string[];
  actorUid: string;
  createdAt: string;
  updatedAt: string;
}

interface ResultEntry {
  index: number;
  result: MutableTaskResult;
}

interface RapidDoseCandidate {
  task: Task;
  result: MutableTaskResult;
}

export const onTaskUpdate = onDocumentUpdated(
  CHECKLIST_PATH,
  async (event): Promise<void> => {
    const snapshot = event.data;
    if (!snapshot) {
      return;
    }

    const beforeData = snapshot.before.data() as Partial<DailyChecklist> | undefined;
    const afterData = snapshot.after.data() as Partial<DailyChecklist> | undefined;
    if (!afterData) {
      return;
    }

    const patientId = event.params.patientId;
    const dateId = event.params.dateId;

    const tasks = toTaskList(afterData.tasks);
    const taskById = new Map<string, Task>(tasks.map((task) => [task.id, task]));
    const beforeResultsById = toResultMap(toMutableTaskResults(beforeData?.results));
    const afterResultEntries = toResultEntries(toMutableTaskResults(afterData.results));

    const changedTaskIds = detectChangedTaskIds(beforeResultsById, afterResultEntries);
    if (changedTaskIds.size === 0) {
      return;
    }

    const nowIso = new Date().toISOString();
    let resultsChanged = false;
    const rapidCandidates: RapidDoseCandidate[] = [];
    const newTaskLogs: TaskLogEntry[] = [];
    const issueCandidates: Issue[] = [];

    for (const taskId of changedTaskIds) {
      const task = taskById.get(taskId);
      const afterEntry = afterResultEntries.map.get(taskId);
      if (!task || !afterEntry) {
        continue;
      }

      const beforeResult = beforeResultsById.get(taskId);
      const result = afterEntry.result;

      if (normalizeStatus(result.status) === 'done') {
        result.status = 'completed';
        resultsChanged = true;
      }

      if (didTransitionToDone(beforeResult, result)) {
        const completedAt = ensureCompletedAt(result, nowIso);
        if (result.completedAt !== completedAt) {
          result.completedAt = completedAt;
          resultsChanged = true;
        }

        const validation = validateRequiredInputs(buildTaskForValidation(task, result));
        const late = checkLate(task.scheduledTime, completedAt, 30);
        if (late && normalizeStatus(result.status) !== 'late') {
          result.status = 'late';
          resultsChanged = true;
        }

        newTaskLogs.push(
          buildCompletionLog({
            patientId,
            dateId,
            task,
            completedAt,
            late,
            missingInputs: validation.missing,
            nowIso,
          }),
        );

        if (late) {
          issueCandidates.push(
            createIssue(patientId, {
              id: sanitizeId(`late_${dateId}_${task.id}`),
              code: 'late',
              checklistDateId: dateId,
              taskId: task.id,
              source: 'task',
              status: 'open',
              title: `Late task: ${task.title}`,
              description: buildLateDescription(task, completedAt),
              createdAt: nowIso,
            }),
          );
        }
      }

      if (task.type === 'insulin_rapid' && didGlucoseChange(beforeResult, result)) {
        rapidCandidates.push({ task, result });
      }
    }

    if (rapidCandidates.length > 0) {
      const profiles = await loadRapidProfiles(patientId);
      for (const candidate of rapidCandidates) {
        const profile = profiles.get(candidate.task.insulinProfileId);
        if (!profile) {
          logger.warn('Rapid profile not found while processing task update.', {
            patientId,
            dateId,
            taskId: candidate.task.id,
            insulinProfileId: candidate.task.insulinProfileId,
          });
          continue;
        }

        const glucose = readFiniteNumber(candidate.result.glucoseMgDl);
        if (!Number.isFinite(glucose)) {
          continue;
        }

        const mealTag = readMealTag(candidate.task, candidate.result);
        const dose = computeRapidDose(mealTag, glucose, profile);
        resultsChanged = applyRapidDoseToResult(candidate.result, dose) || resultsChanged;

        const flags = applySafetyFlags(glucose);
        if (flags.low) {
          issueCandidates.push(
            createIssue(patientId, {
              id: sanitizeId(`low_glucose_${dateId}_${candidate.task.id}`),
              code: 'low_glucose',
              checklistDateId: dateId,
              taskId: candidate.task.id,
              source: 'task',
              status: 'open',
              title: 'Low glucose detected',
              description: `Rapid insulin task "${candidate.task.title}" has low glucose (${glucose} mg/dL).`,
              createdAt: nowIso,
            }),
          );
        } else if (flags.high) {
          issueCandidates.push(
            createIssue(patientId, {
              id: sanitizeId(`high_glucose_${dateId}_${candidate.task.id}`),
              code: 'high_glucose',
              checklistDateId: dateId,
              taskId: candidate.task.id,
              source: 'task',
              status: 'open',
              title: 'High glucose detected',
              description: `Rapid insulin task "${candidate.task.title}" has high glucose (${glucose} mg/dL).`,
              createdAt: nowIso,
            }),
          );
        }
      }
    }

    const existingIssues = toIssueList(afterData.issues);
    const uniqueIssueCandidates = dedupeById(issueCandidates);
    const newIssues = uniqueIssueCandidates.filter(
      (candidate) => !existingIssues.some((issue) => issue.id === candidate.id),
    );
    const mergedIssues = newIssues.length > 0
      ? existingIssues.concat(newIssues)
      : existingIssues;

    const taskLogs = dedupeById(newTaskLogs);
    const shouldUpdateChecklist = resultsChanged || newIssues.length > 0;
    if (!shouldUpdateChecklist && taskLogs.length === 0) {
      return;
    }

    const checklistRef = snapshot.after.ref;
    const patientRef = checklistRef.parent.parent;
    if (!patientRef) {
      return;
    }

    const batch = firestore.batch();
    if (shouldUpdateChecklist) {
      batch.set(
        checklistRef,
        {
          results: afterResultEntries.list,
          issues: mergedIssues,
          updatedAt: nowIso,
        },
        { merge: true },
      );
    }

    for (const issue of newIssues) {
      batch.set(
        patientRef.collection(ISSUES_SUBCOLLECTION).doc(issue.id),
        issue,
        { merge: true },
      );
    }

    for (const taskLog of taskLogs) {
      batch.set(
        patientRef.collection(TASK_LOGS_SUBCOLLECTION).doc(taskLog.id),
        taskLog,
        { merge: true },
      );
    }

    await batch.commit();
  },
);

function buildTaskForValidation(task: Task, result: MutableTaskResult): Task {
  if (task.type !== 'insulin_rapid') {
    return task;
  }

  const glucose = readFiniteNumber(result.glucoseMgDl);
  if (!Number.isFinite(glucose)) {
    return task;
  }

  return {
    ...task,
    glucoseMgDl: glucose,
  } as Task;
}

function ensureCompletedAt(result: MutableTaskResult, fallback: string): string {
  const completedAt = parseIsoDate(result.completedAt);
  if (!completedAt) {
    return fallback;
  }
  return completedAt.toISOString();
}

function didTransitionToDone(
  beforeResult: MutableTaskResult | undefined,
  afterResult: MutableTaskResult,
): boolean {
  return !isDoneStatus(beforeResult?.status) && isDoneStatus(afterResult.status);
}

function isDoneStatus(status: unknown): boolean {
  const normalized = normalizeStatus(status);
  return normalized === 'completed' || normalized === 'done';
}

function normalizeStatus(status: unknown): ResultStatus {
  if (typeof status !== 'string') {
    return 'unknown';
  }

  const normalized = status.trim().toLowerCase();
  if (normalized === 'pending' ||
    normalized === 'completed' ||
    normalized === 'done' ||
    normalized === 'skipped' ||
    normalized === 'failed' ||
    normalized === 'missed' ||
    normalized === 'late') {
    return normalized;
  }

  return 'unknown';
}

function didGlucoseChange(
  beforeResult: MutableTaskResult | undefined,
  afterResult: MutableTaskResult,
): boolean {
  const before = readFiniteNumber(beforeResult?.glucoseMgDl);
  const after = readFiniteNumber(afterResult.glucoseMgDl);

  if (!Number.isFinite(after)) {
    return false;
  }
  if (!Number.isFinite(before)) {
    return true;
  }
  return before !== after;
}

function applyRapidDoseToResult(
  result: MutableTaskResult,
  dose: {base: number; sliding: number; total: number},
): boolean {
  let changed = false;
  changed = writeNumber(result, 'baseUnits', dose.base) || changed;
  changed = writeNumber(result, 'slidingUnits', dose.sliding) || changed;
  changed = writeNumber(result, 'totalUnits', dose.total) || changed;
  changed = writeNumber(result, 'deliveredUnits', dose.total) || changed;
  return changed;
}

function writeNumber(
  target: MutableTaskResult,
  key: 'baseUnits' | 'slidingUnits' | 'totalUnits' | 'deliveredUnits',
  next: number,
): boolean {
  const current = readFiniteNumber(target[key]);
  if (Number.isFinite(current) && numbersEqual(current, next)) {
    return false;
  }

  target[key] = next;
  return true;
}

function numbersEqual(left: number, right: number): boolean {
  return Math.abs(left - right) < 0.00001;
}

function readFiniteNumber(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : Number.NaN;
}

function parseIsoDate(value: unknown): Date | null {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return null;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function buildCompletionLog(input: {
  patientId: string;
  dateId: string;
  task: Task;
  completedAt: string;
  late: boolean;
  missingInputs: string[];
  nowIso: string;
}): TaskLogEntry {
  const status = input.late ? 'late' : 'completed';
  const id = sanitizeId(
    `task_completed_${input.dateId}_${input.task.id}_${toLogTimeKey(input.completedAt)}`,
  );

  return {
    id,
    patientId: input.patientId,
    checklistDateId: input.dateId,
    taskId: input.task.id,
    taskType: input.task.type,
    status,
    event: 'task_completed',
    completedAt: input.completedAt,
    missingInputs: input.missingInputs,
    actorUid: 'system',
    createdAt: input.nowIso,
    updatedAt: input.nowIso,
  };
}

function buildLateDescription(task: Task, completedAt: string): string {
  const scheduled = task.scheduledTime ? `scheduled ${task.scheduledTime}` : 'scheduled time';
  return `Task "${task.title}" (${scheduled}) was completed late at ${completedAt}.`;
}

function readMealTag(task: Task, result: MutableTaskResult): string {
  const fromResult = readNonEmptyString(result.mealTag);
  if (fromResult) {
    return fromResult;
  }

  const fromTask = readNonEmptyString((task as Record<string, unknown>).mealTag);
  if (fromTask) {
    return fromTask;
  }

  return 'none';
}

function readNonEmptyString(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
}

async function loadRapidProfiles(patientId: string): Promise<Map<string, RapidDoseProfile>> {
  const patientRef = firestore.collection('patients').doc(patientId);
  const [patientSnap, profilesSnap] = await Promise.all([
    patientRef.get(),
    patientRef.collection(INSULIN_PROFILES_SUBCOLLECTION).get(),
  ]);

  const profiles = new Map<string, RapidDoseProfile>();

  const inlineProfiles = patientSnap.data()?.insulinProfiles;
  if (Array.isArray(inlineProfiles)) {
    for (const candidate of inlineProfiles) {
      if (!isRecord(candidate)) {
        continue;
      }
      if (candidate.type !== 'rapid') {
        continue;
      }
      if (typeof candidate.id !== 'string' || candidate.id.length === 0) {
        continue;
      }

      profiles.set(candidate.id, candidate as RapidDoseProfile);
    }
  }

  for (const doc of profilesSnap.docs) {
    const data = doc.data();
    if (data.type !== 'rapid') {
      continue;
    }

    profiles.set(doc.id, {
      id: doc.id,
      ...(data as Record<string, unknown>),
    } as RapidDoseProfile);
  }

  return profiles;
}

function detectChangedTaskIds(
  beforeResultsById: Map<string, MutableTaskResult>,
  afterEntries: {
    list: MutableTaskResult[];
    map: Map<string, ResultEntry>;
  },
): Set<string> {
  const changed = new Set<string>();
  const ids = new Set<string>([
    ...beforeResultsById.keys(),
    ...afterEntries.map.keys(),
  ]);

  for (const taskId of ids) {
    const before = beforeResultsById.get(taskId);
    const after = afterEntries.map.get(taskId)?.result;
    if (!after) {
      continue;
    }
    if (!before) {
      changed.add(taskId);
      continue;
    }
    if (hasResultChanged(before, after)) {
      changed.add(taskId);
    }
  }

  return changed;
}

function hasResultChanged(before: MutableTaskResult, after: MutableTaskResult): boolean {
  return before.status !== after.status ||
    before.completedAt !== after.completedAt ||
    before.note !== after.note ||
    before.glucoseMgDl !== after.glucoseMgDl ||
    before.mealTag !== after.mealTag ||
    before.deliveredUnits !== after.deliveredUnits ||
    before.baseUnits !== after.baseUnits ||
    before.slidingUnits !== after.slidingUnits ||
    before.totalUnits !== after.totalUnits;
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
    results.push({ ...(item as Record<string, unknown>) } as MutableTaskResult);
  }

  return results;
}

function toIssueList(value: unknown): Issue[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((item): item is Issue => {
    if (!isRecord(item)) {
      return false;
    }
    return typeof item.id === 'string' &&
      typeof item.title === 'string' &&
      typeof item.status === 'string';
  });
}

function toResultMap(results: MutableTaskResult[]): Map<string, MutableTaskResult> {
  const map = new Map<string, MutableTaskResult>();
  for (const result of results) {
    map.set(result.taskId, result);
  }
  return map;
}

function toResultEntries(results: MutableTaskResult[]): {
  list: MutableTaskResult[];
  map: Map<string, ResultEntry>;
} {
  const map = new Map<string, ResultEntry>();
  results.forEach((result, index) => {
    map.set(result.taskId, { index, result });
  });
  return { list: results, map };
}

function dedupeById<T extends {id: string}>(items: T[]): T[] {
  const map = new Map<string, T>();
  for (const item of items) {
    if (!map.has(item.id)) {
      map.set(item.id, item);
    }
  }
  return Array.from(map.values());
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function sanitizeId(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]/g, '_');
}

function toLogTimeKey(isoDate: string): string {
  const parsed = parseIsoDate(isoDate);
  if (!parsed) {
    return 'unknown';
  }

  const year = parsed.getUTCFullYear();
  const month = String(parsed.getUTCMonth() + 1).padStart(2, '0');
  const day = String(parsed.getUTCDate()).padStart(2, '0');
  const hour = String(parsed.getUTCHours()).padStart(2, '0');
  const minute = String(parsed.getUTCMinutes()).padStart(2, '0');
  const second = String(parsed.getUTCSeconds()).padStart(2, '0');
  return `${year}${month}${day}T${hour}${minute}${second}`;
}
