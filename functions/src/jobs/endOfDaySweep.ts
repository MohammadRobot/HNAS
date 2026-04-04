import {
  type DocumentData,
  type DocumentReference,
} from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {firestore} from '../lib/firestore';
import {createIssue} from '../lib/rulesEngine';
import {
  getDateIdForTimeZone,
  normalizeTimeZone,
  shouldRunEndOfDaySweepNow,
} from '../lib/timezone';
import {
  type DailyChecklist,
  type Issue,
  type Task,
  type TaskResult,
} from '../lib/types';

const DAILY_CHECKLISTS_COLLECTION = 'dailyChecklists';
const TASK_LOGS_SUBCOLLECTION = 'taskLogs';
const ISSUES_SUBCOLLECTION = 'issues';
const REPORTS_COLLECTION = 'reports';
const REPORTS_DAILY_DOC_ID = 'daily';
const REPORTS_BY_DATE_SUBCOLLECTION = 'byDate';

const AUTO_MISSED_NOTE = 'Auto-marked as missed by end-of-day sweep.';

export const endOfDaySweep = onSchedule(
    {
      schedule: '*/15 * * * *',
      timeZone: 'UTC',
    },
    async () => {
      const now = new Date();
      const patientsSnapshot = await firestore
          .collection('patients')
          .where('active', '==', true)
          .get();

      logger.info('Starting end-of-day sweep.', {
        triggerAt: now.toISOString(),
        patientCount: patientsSnapshot.size,
      });

      for (const patientDoc of patientsSnapshot.docs) {
        const patientRef = patientDoc.ref as DocumentReference<DocumentData>;
        const patientTimeZone = normalizeTimeZone(patientDoc.data().timezone);
        if (!shouldRunEndOfDaySweepNow(now, patientTimeZone)) {
          continue;
        }

        const dateId = getDateIdForTimeZone(now, patientTimeZone);
        const checklistRef = patientRef
            .collection(DAILY_CHECKLISTS_COLLECTION)
            .doc(dateId) as DocumentReference<DailyChecklist>;

        try {
          const summary = await sweepChecklistForPatient(
              patientRef,
              checklistRef,
              dateId,
          );

          if (!summary.hasChecklist) {
            continue;
          }

          logger.info('Completed end-of-day sweep for checklist.', {
            dateId,
            patientId: patientRef.id,
            patientTimeZone,
            missedCreated: summary.missedCreated,
            done: summary.counts.done,
            missed: summary.counts.missed,
            late: summary.counts.late,
            skipped: summary.counts.skipped,
          });
        } catch (error) {
          logger.error('End-of-day sweep failed for checklist.', {
            dateId,
            patientId: patientRef.id,
            patientTimeZone,
            checklistPath: checklistRef.path,
            error: error instanceof Error ? error.message : String(error),
          });
        }
      }
    },
);

interface SweepSummary {
  hasChecklist: boolean;
  missedCreated: number;
  counts: DailyCounts;
}

interface DailyCounts {
  done: number;
  missed: number;
  late: number;
  skipped: number;
}

async function sweepChecklistForPatient(
    patientRef: DocumentReference<DocumentData>,
    checklistRef: DocumentReference<DailyChecklist>,
    dateId: string,
): Promise<SweepSummary> {
  const reportRef = patientRef
      .collection(REPORTS_COLLECTION)
      .doc(REPORTS_DAILY_DOC_ID)
      .collection(REPORTS_BY_DATE_SUBCOLLECTION)
      .doc(dateId);

  return firestore.runTransaction(async (transaction) => {
    const freshChecklistSnap = await transaction.get(checklistRef);
    const reportSnap = await transaction.get(reportRef);

    if (!freshChecklistSnap.exists) {
      return {
        hasChecklist: false,
        missedCreated: 0,
        counts: {done: 0, missed: 0, late: 0, skipped: 0},
      };
    }

    const checklist = freshChecklistSnap.data() as Partial<DailyChecklist>;
    const tasks = toTaskList(checklist.tasks);
    const existingResults = toTaskResultList(checklist.results);

    const nowIso = new Date().toISOString();
    const sweep = markPendingTasksAsMissed(tasks, existingResults, nowIso);
    const counts = aggregateDailyCounts(tasks, sweep.results);

    const newIssues = buildMissedTaskIssues(
        patientRef.id,
        dateId,
        sweep.missedTasks,
        nowIso,
    );
    const mergedIssues = mergeIssues(toIssueList(checklist.issues), newIssues);

    transaction.set(
        checklistRef,
        {
          results: sweep.results,
          issues: mergedIssues,
          updatedAt: nowIso,
        },
        {merge: true},
    );

    for (const task of sweep.missedTasks) {
      const taskLog = buildTaskLog(patientRef.id, dateId, task, nowIso);
      transaction.set(
          patientRef.collection(TASK_LOGS_SUBCOLLECTION).doc(taskLog.id),
          taskLog,
          {merge: true},
      );
    }

    for (const issue of newIssues) {
      transaction.set(
          patientRef.collection(ISSUES_SUBCOLLECTION).doc(issue.id),
          issue,
          {merge: true},
      );
    }

    const existingReportData = reportSnap.data();
    const createdAt = typeof existingReportData?.createdAt === 'string' ?
      existingReportData.createdAt :
      nowIso;

    transaction.set(
        reportRef,
        {
          id: dateId,
          dateId,
          patientId: patientRef.id,
          done: counts.done,
          missed: counts.missed,
          late: counts.late,
          skipped: counts.skipped,
          createdAt,
          updatedAt: nowIso,
        },
        {merge: false},
    );

    return {
      hasChecklist: true,
      missedCreated: sweep.missedTasks.length,
      counts,
    };
  });
}

interface SweepResult {
  results: TaskResult[];
  missedTasks: Task[];
}

function markPendingTasksAsMissed(
    tasks: Task[],
    existingResults: TaskResult[],
    nowIso: string,
): SweepResult {
  const taskIds = new Set(tasks.map((task) => task.id));
  const resultByTaskId = new Map<string, TaskResult>();

  for (const result of existingResults) {
    resultByTaskId.set(result.taskId, result);
  }

  const missedTasks: Task[] = [];
  const nextResults: TaskResult[] = [];

  for (const task of tasks) {
    const current = resultByTaskId.get(task.id);
    const isPending = !current || current.status === 'pending';

    if (isPending) {
      missedTasks.push(task);
      nextResults.push(createMissedResult(task, current, nowIso));
      continue;
    }

    nextResults.push(current);
  }

  for (const result of existingResults) {
    if (!taskIds.has(result.taskId)) {
      nextResults.push(result);
    }
  }

  return {results: nextResults, missedTasks};
}

function createMissedResult(
    task: Task,
    existing: TaskResult | undefined,
    nowIso: string,
): TaskResult {
  const note = appendAutoMissedNote(existing?.note);
  const completedAt = existing?.completedAt ?? nowIso;

  if (task.type === 'medicine') {
    return {
      type: 'medicine',
      taskId: task.id,
      status: 'missed',
      completedAt,
      note,
    };
  }

  if (task.type === 'procedure') {
    return {
      type: 'procedure',
      taskId: task.id,
      status: 'missed',
      completedAt,
      note,
    };
  }

  if (task.type === 'insulin_rapid') {
    return {
      type: 'insulin_rapid',
      taskId: task.id,
      status: 'missed',
      completedAt,
      note,
    };
  }

  return {
    type: 'insulin_basal',
    taskId: task.id,
    status: 'missed',
    completedAt,
    note,
  };
}

function appendAutoMissedNote(existingNote?: string): string {
  if (!existingNote || existingNote.trim().length === 0) {
    return AUTO_MISSED_NOTE;
  }

  if (existingNote.includes(AUTO_MISSED_NOTE)) {
    return existingNote;
  }

  return `${existingNote} ${AUTO_MISSED_NOTE}`;
}

function buildMissedTaskIssues(
    patientId: string,
    dateId: string,
    missedTasks: Task[],
    nowIso: string,
): Issue[] {
  return missedTasks.map((task) => {
    const issueId = sanitizeId(`missed_${dateId}_${task.id}`);
    const code = task.type === 'insulin_rapid' || task.type === 'insulin_basal' ?
      'missed_insulin' :
      'missed_other';

    return createIssue(patientId, {
      id: issueId,
      code,
      checklistDateId: dateId,
      taskId: task.id,
      source: 'task',
      status: 'open',
      title: `Missed task: ${task.title}`,
      description: buildIssueDescription(task),
      createdAt: nowIso,
    });
  });
}

function buildIssueDescription(task: Task): string {
  const atText = task.scheduledTime ? ` at ${task.scheduledTime}` : '';
  return `Task "${task.title}"${atText} was not completed by end of day.`;
}

function mergeIssues(existingIssues: Issue[], newIssues: Issue[]): Issue[] {
  const mergedById = new Map<string, Issue>();

  for (const issue of existingIssues) {
    mergedById.set(issue.id, issue);
  }

  for (const issue of newIssues) {
    mergedById.set(issue.id, issue);
  }

  return Array.from(mergedById.values());
}

interface TaskLogEntry {
  id: string;
  patientId: string;
  checklistDateId: string;
  taskId: string;
  taskType: Task['type'];
  taskTitle: string;
  scheduledTime?: string;
  status: 'missed';
  event: 'auto_marked_missed';
  actorUid: 'system';
  createdAt: string;
  updatedAt: string;
}

function buildTaskLog(
    patientId: string,
    dateId: string,
    task: Task,
    nowIso: string,
): TaskLogEntry {
  const logId = sanitizeId(`missed_${dateId}_${task.id}`);
  return {
    id: logId,
    patientId,
    checklistDateId: dateId,
    taskId: task.id,
    taskType: task.type,
    taskTitle: task.title,
    scheduledTime: task.scheduledTime,
    status: 'missed',
    event: 'auto_marked_missed',
    actorUid: 'system',
    createdAt: nowIso,
    updatedAt: nowIso,
  };
}

function aggregateDailyCounts(tasks: Task[], results: TaskResult[]): DailyCounts {
  const resultByTaskId = new Map<string, TaskResult>();
  for (const result of results) {
    resultByTaskId.set(result.taskId, result);
  }

  const counts: DailyCounts = {
    done: 0,
    missed: 0,
    late: 0,
    skipped: 0,
  };

  for (const task of tasks) {
    const status = resultByTaskId.get(task.id)?.status ?? 'missed';

    if (status === 'completed') {
      counts.done += 1;
      continue;
    }

    if (status === 'skipped') {
      counts.skipped += 1;
      continue;
    }

    if (status === 'late') {
      counts.late += 1;
      continue;
    }

    if (status === 'pending' || status === 'failed' || status === 'missed') {
      counts.missed += 1;
    }
  }

  return counts;
}

function toTaskList(value: unknown): Task[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((task): task is Task => {
    if (!isRecord(task)) {
      return false;
    }

    return typeof task.id === 'string' &&
      typeof task.type === 'string' &&
      typeof task.title === 'string';
  });
}

function toTaskResultList(value: unknown): TaskResult[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((result): result is TaskResult => {
    if (!isRecord(result)) {
      return false;
    }

    return typeof result.taskId === 'string' &&
      typeof result.type === 'string' &&
      typeof result.status === 'string';
  });
}

function toIssueList(value: unknown): Issue[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((issue): issue is Issue => {
    if (!isRecord(issue)) {
      return false;
    }

    return typeof issue.id === 'string' &&
      typeof issue.title === 'string' &&
      typeof issue.status === 'string';
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function sanitizeId(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]/g, '_');
}
