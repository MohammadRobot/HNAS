import {
  type DocumentData,
  type QueryDocumentSnapshot,
} from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {
  type ChecklistSourceRecord,
  generateChecklistTasks,
} from '../lib/checklistGenerator';
import {firestore, patientSubcollectionRef} from '../lib/firestore';
import {
  getDateIdForTimeZone,
  normalizeTimeZone,
  shouldGenerateChecklistNow,
} from '../lib/timezone';
import {
  type DailyChecklist,
  type Issue,
  type Task,
  type TaskResult,
} from '../lib/types';

const PATIENTS_COLLECTION = 'patients';
const MEDICINES_SUBCOLLECTION = 'medicines';
const PROCEDURES_SUBCOLLECTION = 'procedures';
const INSULIN_PROFILES_SUBCOLLECTION = 'insulinProfiles';
const DAILY_CHECKLISTS_SUBCOLLECTION = 'dailyChecklists';

export const generateDailyChecklists = onSchedule(
    {
      schedule: '*/15 * * * *',
      timeZone: 'UTC',
    },
    async () => {
      const now = new Date();
      const patientsSnapshot = await firestore
          .collection(PATIENTS_COLLECTION)
          .where('active', '==', true)
          .get();

      logger.info('Starting daily checklist generation.', {
        triggerAt: now.toISOString(),
        patientCount: patientsSnapshot.size,
      });

      for (const patientDoc of patientsSnapshot.docs) {
        const patientId = patientDoc.id;
        const patientData = patientDoc.data();
        const patientTimeZone = normalizeTimeZone(patientData.timezone);
        if (!shouldGenerateChecklistNow(now, patientTimeZone)) {
          continue;
        }

        const dateId = getDateIdForTimeZone(now, patientTimeZone);

        try {
          const [medicinesSnapshot, proceduresSnapshot, insulinSnapshot] = await Promise.all([
            patientSubcollectionRef(patientId, MEDICINES_SUBCOLLECTION)
                .where('active', '==', true)
                .get(),
            patientSubcollectionRef(patientId, PROCEDURES_SUBCOLLECTION)
                .where('active', '==', true)
                .get(),
            patientSubcollectionRef(patientId, INSULIN_PROFILES_SUBCOLLECTION)
                .where('active', '==', true)
                .get(),
          ]);

          const medicines = medicinesSnapshot.docs.map(toSourceRecord);
          const procedures = proceduresSnapshot.docs.map(toSourceRecord);
          const insulinProfiles = resolveInsulinProfiles(
              patientData,
              insulinSnapshot.docs.map(toSourceRecord),
          );

          const tasks = generateChecklistTasks({
            patientId,
            dateId,
            medicines,
            procedures,
            insulinProfiles,
          });

          await upsertDailyChecklist({
            patientId,
            dateId,
            tasks,
          });

          logger.info('Generated daily checklist.', {
            patientId,
            dateId,
            patientTimeZone,
            taskCount: tasks.length,
          });
        } catch (error) {
          logger.error('Failed to generate daily checklist for patient.', {
            patientId,
            dateId,
            patientTimeZone,
            error: error instanceof Error ? error.message : String(error),
          });
        }
      }
    },
);

function toSourceRecord(
    snapshot: QueryDocumentSnapshot<DocumentData>,
): ChecklistSourceRecord {
  return {
    id: snapshot.id,
    ...(snapshot.data() as Record<string, unknown>),
  };
}

function resolveInsulinProfiles(
    patientDocData: DocumentData,
    subcollectionProfiles: ChecklistSourceRecord[],
): ChecklistSourceRecord[] {
  const inlineProfiles = extractInlineInsulinProfiles(patientDocData);
  if (subcollectionProfiles.length === 0) {
    return inlineProfiles;
  }

  const merged = new Map<string, ChecklistSourceRecord>();
  for (const inlineProfile of inlineProfiles) {
    merged.set(inlineProfile.id, inlineProfile);
  }
  for (const profile of subcollectionProfiles) {
    merged.set(profile.id, profile);
  }

  return Array.from(merged.values());
}

function extractInlineInsulinProfiles(patientDocData: DocumentData): ChecklistSourceRecord[] {
  const rawProfiles = patientDocData.insulinProfiles;
  if (!Array.isArray(rawProfiles)) {
    return [];
  }

  const profiles: ChecklistSourceRecord[] = [];
  rawProfiles.forEach((rawProfile, index) => {
    if (!isRecord(rawProfile)) {
      return;
    }

    const id = typeof rawProfile.id === 'string' && rawProfile.id.length > 0 ?
      rawProfile.id :
      `inline_${index + 1}`;
    const active = typeof rawProfile.active !== 'boolean' || rawProfile.active;
    if (!active) {
      return;
    }

    profiles.push({
      id,
      ...rawProfile,
    });
  });

  return profiles;
}

interface UpsertChecklistInput {
  patientId: string;
  dateId: string;
  tasks: Task[];
}

async function upsertDailyChecklist(input: UpsertChecklistInput): Promise<void> {
  const checklistRef = patientSubcollectionRef<DailyChecklist>(
      input.patientId,
      DAILY_CHECKLISTS_SUBCOLLECTION,
  ).doc(input.dateId);

  await firestore.runTransaction(async (transaction) => {
    const existingSnapshot = await transaction.get(checklistRef);
    const existingData = existingSnapshot.exists ?
      (existingSnapshot.data() as Partial<DailyChecklist>) :
      undefined;

    const now = new Date().toISOString();
    const taskIds = new Set(input.tasks.map((task) => task.id));
    const results = readExistingResults(existingData?.results, taskIds);
    const issues = readExistingIssues(existingData?.issues);
    const createdAt = typeof existingData?.createdAt === 'string' ?
      existingData.createdAt :
      now;

    const checklist: DailyChecklist = {
      id: input.dateId,
      patientId: input.patientId,
      dateId: input.dateId,
      tasks: input.tasks,
      results,
      issues,
      createdAt,
      updatedAt: now,
    };

    transaction.set(checklistRef, checklist, {merge: false});
  });
}

function readExistingResults(
    existingResults: unknown,
    taskIds: Set<string>,
): TaskResult[] {
  if (!Array.isArray(existingResults)) {
    return [];
  }

  return existingResults.filter((result): result is TaskResult => {
    if (!isRecord(result)) {
      return false;
    }

    const taskId = result.taskId;
    const type = result.type;
    return typeof taskId === 'string' &&
      taskIds.has(taskId) &&
      isAllowedTaskResultType(type);
  });
}

function readExistingIssues(existingIssues: unknown): Issue[] {
  if (!Array.isArray(existingIssues)) {
    return [];
  }

  return existingIssues.filter((issue): issue is Issue => isRecord(issue));
}

function isAllowedTaskResultType(value: unknown): boolean {
  return value === 'medicine' ||
    value === 'procedure' ||
    value === 'insulin_rapid' ||
    value === 'insulin_basal';
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
