import {type Task} from './types';

export interface VisitTaskResult {
  taskId: string;
  status?: string;
  inputs?: Record<string, unknown>;
}

export interface VisitProgress {
  taskCount: number;
  completedTaskCount: number;
  pendingTaskCount: number;
  issueCount: number;
  currentTaskId?: string;
}

const COMPLETED_STATUSES = new Set([
  'completed',
  'done',
  'late',
  'skipped',
  'failed',
  'missed',
]);

const ATTENTION_STATUSES = new Set([
  'skipped',
  'failed',
  'missed',
]);

/**
 * Derives visit progress from the existing checklist. The checklist remains
 * the source of truth; visit documents only cache these values for the Today
 * experience.
 *
 * @param {Task[]} tasks Checklist tasks in display order.
 * @param {VisitTaskResult[]} results Existing recorded task outcomes.
 * @return {VisitProgress} The progress snapshot for a visit.
 */
export function summarizeVisitProgress(
    tasks: Task[],
    results: VisitTaskResult[],
): VisitProgress {
  const resultByTaskId = new Map<string, VisitTaskResult>();
  for (const result of results) {
    resultByTaskId.set(result.taskId, result);
  }

  let completedTaskCount = 0;
  let issueCount = 0;
  let currentTaskId: string | undefined;

  for (const task of tasks) {
    const result = resultByTaskId.get(task.id);
    const status = normalizeStatus(result?.status);
    if (COMPLETED_STATUSES.has(status)) {
      completedTaskCount += 1;
    } else if (!currentTaskId) {
      currentTaskId = task.id;
    }

    if (ATTENTION_STATUSES.has(status) || hasAttentionOutcome(result?.inputs)) {
      issueCount += 1;
    }
  }

  return {
    taskCount: tasks.length,
    completedTaskCount,
    pendingTaskCount: Math.max(0, tasks.length - completedTaskCount),
    issueCount,
    currentTaskId,
  };
}

export function findVisitStartTime(tasks: Task[]): string | undefined {
  return tasks
      .map((task) => task.scheduledTime)
      .filter((value): value is string => (
        typeof value === 'string' && /^\d{2}:\d{2}$/.test(value)
      ))
      .sort()[0];
}

function normalizeStatus(value: unknown): string {
  return typeof value === 'string' ? value.trim().toLowerCase() : 'pending';
}

function hasAttentionOutcome(inputs: unknown): boolean {
  if (!inputs || typeof inputs !== 'object' || Array.isArray(inputs)) {
    return false;
  }
  const reason = (inputs as Record<string, unknown>).outcomeReason;
  return reason === 'patient_declined' ||
    reason === 'unable_to_complete' ||
    reason === 'needs_help';
}
