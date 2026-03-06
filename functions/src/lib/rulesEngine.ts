import { toDateId } from './firestore';
import {
  type DailyChecklist,
  type Issue,
  type IssueSeverity,
  type IssueStatus,
  type Task,
} from './types';

export type IssueRuleCode =
  | 'low_glucose'
  | 'high_glucose'
  | 'missed_insulin'
  | 'missed_other'
  | 'late'
  | 'other';

export interface RequiredInputValidation {
  valid: boolean;
  missing: string[];
}

export interface CreateIssueInput {
  id?: string;
  code?: IssueRuleCode;
  checklistDateId?: string;
  taskId?: string;
  source?: Issue['source'];
  status?: IssueStatus;
  severity?: IssueSeverity;
  title: string;
  description: string;
  createdAt?: string;
}

export interface DuplicateTaskGroup {
  key: string;
  taskIds: string[];
  tasks: Task[];
}

type RuntimeTaskInputs = Record<string, unknown>;
type TaskWithRuntimeInputs = Task & {
  inputs?: RuntimeTaskInputs;
  glucoseMgDl?: unknown;
};

export function checkLate(
  scheduledTime: string | undefined,
  completedAt: string | Date | undefined,
  thresholdMin = 30,
): boolean {
  const scheduledMinutes = parseScheduledMinutes(scheduledTime);
  const completedDate = parseDate(completedAt);
  if (scheduledMinutes === null || !completedDate) {
    return false;
  }

  const clampedThreshold = Number.isFinite(thresholdMin) ? Math.max(0, thresholdMin) : 30;
  const completedMinutes = completedDate.getUTCHours() * 60 + completedDate.getUTCMinutes();

  let diff = completedMinutes - scheduledMinutes;
  if (diff < -720) {
    diff += 1440;
  } else if (diff > 720) {
    diff -= 1440;
  }

  return diff > clampedThreshold;
}

export function validateRequiredInputs(task: Task): RequiredInputValidation {
  const missing: string[] = [];
  const candidate = task as TaskWithRuntimeInputs;

  if (!isNonEmptyString(task.id)) {
    missing.push('id');
  }
  if (!isNonEmptyString(task.title)) {
    missing.push('title');
  }

  if (task.type === 'medicine' && !isNonEmptyString(task.medicineId)) {
    missing.push('medicineId');
  }

  if (task.type === 'procedure' && !isNonEmptyString(task.procedureId)) {
    missing.push('procedureId');
  }

  if (task.type === 'insulin_rapid' || task.type === 'insulin_basal') {
    if (!isNonEmptyString(task.insulinProfileId)) {
      missing.push('insulinProfileId');
    }
  }

  if (task.type === 'insulin_rapid') {
    const glucose = readNumberInput(candidate, 'glucoseMgDl');
    if (!Number.isFinite(glucose)) {
      missing.push('glucoseMgDl');
    }
  }

  return {
    valid: missing.length === 0,
    missing,
  };
}

export function createIssue(patientId: string, input: CreateIssueInput): Issue {
  const createdAt = isNonEmptyString(input.createdAt)
    ? input.createdAt
    : new Date().toISOString();
  const checklistDateId = isNonEmptyString(input.checklistDateId)
    ? input.checklistDateId
    : toDateId(createdAt);
  const severity = input.severity ?? mapIssueSeverity(input.code ?? 'other');

  const rawId = input.id ??
    [
      input.code ?? 'issue',
      checklistDateId,
      input.taskId ?? createdAt,
    ].join('_');

  return {
    id: sanitizeId(rawId),
    patientId,
    checklistDateId,
    source: input.source ?? 'manual',
    severity,
    status: input.status ?? 'open',
    title: input.title,
    description: input.description,
    taskId: input.taskId,
    createdAt,
  };
}

export function detectDuplicateTasks(checklist: DailyChecklist): DuplicateTaskGroup[] {
  const groups = new Map<string, Task[]>();

  for (const task of checklist.tasks) {
    const key = buildDuplicateKey(task);
    const current = groups.get(key) ?? [];
    current.push(task);
    groups.set(key, current);
  }

  const duplicates: DuplicateTaskGroup[] = [];
  for (const [key, tasks] of groups.entries()) {
    if (tasks.length < 2) {
      continue;
    }

    duplicates.push({
      key,
      taskIds: tasks.map((task) => task.id),
      tasks,
    });
  }

  return duplicates;
}

export function mapIssueSeverity(code: IssueRuleCode): IssueSeverity {
  if (code === 'low_glucose' || code === 'high_glucose' || code === 'missed_insulin') {
    return 'critical';
  }

  if (code === 'missed_other' || code === 'late') {
    return 'warning';
  }

  return 'medium';
}

export function mapMissedTaskSeverity(task: Task): IssueSeverity {
  if (task.type === 'insulin_rapid' || task.type === 'insulin_basal') {
    return mapIssueSeverity('missed_insulin');
  }

  return mapIssueSeverity('missed_other');
}

function readNumberInput(task: TaskWithRuntimeInputs, key: string): number {
  const directValue = (task as Record<string, unknown>)[key];
  if (typeof directValue === 'number' && Number.isFinite(directValue)) {
    return directValue;
  }

  const inputValue = task.inputs?.[key];
  if (typeof inputValue === 'number' && Number.isFinite(inputValue)) {
    return inputValue;
  }

  return Number.NaN;
}

function buildDuplicateKey(task: Task): string {
  if (task.type === 'medicine') {
    return ['medicine', task.medicineId, task.scheduledTime ?? ''].join('|');
  }

  if (task.type === 'procedure') {
    return ['procedure', task.procedureId, task.scheduledTime ?? ''].join('|');
  }

  if (task.type === 'insulin_rapid') {
    return ['insulin_rapid', task.insulinProfileId, task.scheduledTime ?? ''].join('|');
  }

  return ['insulin_basal', task.insulinProfileId, task.scheduledTime ?? ''].join('|');
}

function parseScheduledMinutes(scheduledTime: string | undefined): number | null {
  if (!isNonEmptyString(scheduledTime)) {
    return null;
  }

  const match = /^(\d{1,2}):(\d{2})(?::\d{2})?$/.exec(scheduledTime.trim());
  if (!match) {
    return null;
  }

  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (!Number.isInteger(hour) || !Number.isInteger(minute)) {
    return null;
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }

  return hour * 60 + minute;
}

function parseDate(value: string | Date | undefined): Date | null {
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }

  if (!isNonEmptyString(value)) {
    return null;
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function sanitizeId(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]/g, '_');
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

