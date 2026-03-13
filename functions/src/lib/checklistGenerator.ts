import {type DateId, type Task} from './types';

export interface ChecklistSourceRecord {
  id: string;
  [key: string]: unknown;
}

export interface GenerateChecklistTasksInput {
  patientId: string;
  dateId: DateId;
  medicines: ChecklistSourceRecord[];
  procedures: ChecklistSourceRecord[];
  insulinProfiles: ChecklistSourceRecord[];
}

interface ScheduleEntry {
  time: string;
  units?: number;
  doseAmount?: number;
  doseUnit?: string;
}

export function generateChecklistTasks(input: GenerateChecklistTasksInput): Task[] {
  const tasks: Task[] = [];
  tasks.push(...buildMedicineTasks(input.medicines));
  tasks.push(...buildProcedureTasks(input.procedures));
  tasks.push(...buildRapidInsulinTasks(input.insulinProfiles));
  tasks.push(...buildBasalInsulinTasks(input.insulinProfiles));

  return tasks.sort((left, right) => {
    const leftTime = left.scheduledTime ?? '99:99';
    const rightTime = right.scheduledTime ?? '99:99';
    if (leftTime !== rightTime) {
      return leftTime.localeCompare(rightTime);
    }
    return left.id.localeCompare(right.id);
  });
}

function buildMedicineTasks(medicines: ChecklistSourceRecord[]): Task[] {
  const tasks: Task[] = [];
  for (const medicine of medicines) {
    if (!isActive(medicine)) {
      continue;
    }

    const name = readString(medicine.name) ?? 'Medicine';
    const instructions = readString(medicine.instructions);
    const defaultDoseAmount = readNumber(medicine.doseAmount);
    const defaultDoseUnit = readString(medicine.doseUnit);
    const scheduleEntries = extractScheduleEntries(medicine);

    scheduleEntries.forEach((entry, index) => {
      tasks.push({
        id: buildTaskId('medicine', medicine.id, entry.time, index),
        type: 'medicine',
        medicineId: medicine.id,
        title: `Medicine: ${name}`,
        required: true,
        scheduledTime: entry.time,
        plannedDoseAmount: entry.doseAmount ?? defaultDoseAmount,
        plannedDoseUnit: entry.doseUnit ?? defaultDoseUnit,
        notes: instructions,
      });
    });
  }
  return tasks;
}

function buildProcedureTasks(procedures: ChecklistSourceRecord[]): Task[] {
  const tasks: Task[] = [];
  for (const procedure of procedures) {
    if (!isActive(procedure)) {
      continue;
    }

    const name = readString(procedure.name) ?? 'Procedure';
    const instructions = readString(procedure.instructions);
    const scheduleEntries = extractScheduleEntries(procedure);

    scheduleEntries.forEach((entry, index) => {
      tasks.push({
        id: buildTaskId('procedure', procedure.id, entry.time, index),
        type: 'procedure',
        procedureId: procedure.id,
        title: `Procedure: ${name}`,
        required: true,
        scheduledTime: entry.time,
        notes: instructions,
      });
    });
  }
  return tasks;
}

function buildRapidInsulinTasks(insulinProfiles: ChecklistSourceRecord[]): Task[] {
  const tasks: Task[] = [];
  for (const profile of insulinProfiles) {
    if (!isActive(profile) || readString(profile.type) !== 'rapid') {
      continue;
    }

    const label = readString(profile.label) ?? readString(profile.insulinName) ?? 'Rapid Insulin';
    const scheduleEntries = extractScheduleEntries(profile);

    scheduleEntries.forEach((entry, index) => {
      tasks.push({
        id: buildTaskId('insulin_rapid', profile.id, entry.time, index),
        type: 'insulin_rapid',
        insulinProfileId: profile.id,
        title: `Insulin (Rapid): ${label}`,
        required: true,
        scheduledTime: entry.time,
        plannedUnits: entry.units,
        notes: mergeNotes(
            readString(profile.notes),
            'Requires glucose input before dosing.',
        ),
      });
    });
  }
  return tasks;
}

function buildBasalInsulinTasks(insulinProfiles: ChecklistSourceRecord[]): Task[] {
  const tasks: Task[] = [];
  for (const profile of insulinProfiles) {
    if (!isActive(profile) || readString(profile.type) !== 'basal') {
      continue;
    }

    const label = readString(profile.label) ?? readString(profile.insulinName) ?? 'Basal Insulin';
    const scheduleEntries = extractScheduleEntries(profile);

    scheduleEntries.forEach((entry, index) => {
      const plannedUnits = entry.units ?? readNumber(profile.fixedUnits);
      tasks.push({
        id: buildTaskId('insulin_basal', profile.id, entry.time, index),
        type: 'insulin_basal',
        insulinProfileId: profile.id,
        title: `Insulin (Basal): ${label}`,
        required: true,
        scheduledTime: entry.time,
        plannedUnits,
        notes: readString(profile.notes) ?? 'Fixed basal dose.',
      });
    });
  }
  return tasks;
}

function extractScheduleEntries(source: ChecklistSourceRecord): ScheduleEntry[] {
  const entries: ScheduleEntry[] = [];
  collectEntries(entries, source.time);
  collectEntries(entries, source.times);
  collectEntries(entries, source.scheduleTimes);

  const scheduleValue = source.schedule;
  if (isRecord(scheduleValue)) {
    collectEntries(entries, scheduleValue.time);
    collectEntries(entries, scheduleValue.times);
    collectEntries(entries, scheduleValue.entries);
  } else {
    collectEntries(entries, scheduleValue);
  }

  return dedupeAndSortSchedule(entries);
}

function collectEntries(target: ScheduleEntry[], value: unknown): void {
  if (typeof value === 'string') {
    const time = normalizeTime(value);
    if (time) {
      target.push({time});
    }
    return;
  }

  if (Array.isArray(value)) {
    value.forEach((entry) => collectEntries(target, entry));
    return;
  }

  if (!isRecord(value)) {
    return;
  }

  const time = normalizeTime(
      readString(value.time) ??
      readString(value.at) ??
      readString(value.scheduledTime) ??
      readString(value.startTime),
  );
  if (!time) {
    return;
  }

  target.push({
    time,
    units: readNumber(
        value.units ??
        value.plannedUnits ??
        value.fixedUnits ??
        value.doseUnits ??
        value.unitsPerDose ??
        value.unitsPerHour,
    ),
    doseAmount: readNumber(value.doseAmount ?? value.amount),
    doseUnit: readString(value.doseUnit ?? value.unit),
  });
}

function dedupeAndSortSchedule(entries: ScheduleEntry[]): ScheduleEntry[] {
  const seen = new Set<string>();
  const deduped: ScheduleEntry[] = [];

  for (const entry of entries) {
    const key = [
      entry.time,
      entry.units ?? '',
      entry.doseAmount ?? '',
      entry.doseUnit ?? '',
    ].join('|');

    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    deduped.push(entry);
  }

  return deduped.sort((left, right) => left.time.localeCompare(right.time));
}

function buildTaskId(prefix: string, sourceId: string, time: string, index: number): string {
  const safeSourceId = sourceId.replace(/[^a-zA-Z0-9_-]/g, '_');
  const safeTime = time.replace(':', '');
  return `${prefix}_${safeSourceId}_${safeTime}_${index + 1}`;
}

function normalizeTime(value: string | undefined): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  if (/^\d{1,2}:\d{2}$/.test(trimmed)) {
    const [hour, minute] = trimmed.split(':');
    return `${hour.padStart(2, '0')}:${minute}`;
  }

  if (/^\d{1,2}:\d{2}:\d{2}$/.test(trimmed)) {
    const [hour, minute] = trimmed.split(':');
    return `${hour.padStart(2, '0')}:${minute}`;
  }

  return null;
}

function readString(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : undefined;
}

function readNumber(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isActive(value: ChecklistSourceRecord): boolean {
  if (typeof value.active !== 'boolean') {
    return true;
  }
  return value.active;
}

function mergeNotes(primary?: string, secondary?: string): string | undefined {
  const primaryValue = readString(primary);
  const secondaryValue = readString(secondary);
  if (primaryValue && secondaryValue) {
    return `${primaryValue} ${secondaryValue}`;
  }
  return primaryValue ?? secondaryValue;
}
