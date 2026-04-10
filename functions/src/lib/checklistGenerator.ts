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
  tasks.push(...buildMedicineTasks(input.medicines, input.dateId));
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

function buildMedicineTasks(medicines: ChecklistSourceRecord[], dateId: DateId): Task[] {
  const tasks: Task[] = [];
  for (const medicine of medicines) {
    if (!isActive(medicine)) {
      continue;
    }
    if (!isMedicineScheduledForDate(medicine, dateId)) {
      continue;
    }

    const name = readString(medicine.name) ?? 'Medicine';
    const instructions = readString(medicine.instructions);
    const defaultDoseAmount = readNumber(medicine.doseAmount);
    const defaultDoseUnit = readString(medicine.doseUnit);
    const scheduleEntries = extractScheduleEntries(medicine);

    scheduleEntries.forEach((entry, index) => {
      tasks.push(compactUndefined({
        id: buildTaskId('medicine', medicine.id, entry.time, index),
        type: 'medicine',
        medicineId: medicine.id,
        title: `Medicine: ${name}`,
        required: true,
        scheduledTime: entry.time,
        plannedDoseAmount: entry.doseAmount ?? defaultDoseAmount,
        plannedDoseUnit: entry.doseUnit ?? defaultDoseUnit,
        notes: instructions,
      }) as unknown as Task);
    });
  }
  return tasks;
}

interface DateParts {
  year: number;
  month: number;
  day: number;
}

function isMedicineScheduledForDate(
    medicine: ChecklistSourceRecord,
    dateId: DateId,
): boolean {
  const targetDate = parseDateId(dateId);
  if (!targetDate) {
    return true;
  }

  const startDate = parseDateId(readString(medicine.startDate));
  if (startDate && compareDateParts(targetDate, startDate) < 0) {
    return false;
  }

  const recurrenceMode = readString(medicine.recurrenceMode)?.toLowerCase() ?? 'daily';
  if (recurrenceMode !== 'interval') {
    return true;
  }

  if (!startDate) {
    return true;
  }

  const recurrenceEvery = readPositiveInteger(medicine.recurrenceEvery) ?? 1;
  const recurrenceUnit = normalizeRecurrenceUnit(readString(medicine.recurrenceUnit)) ?? 'days';

  if (recurrenceUnit === 'days') {
    const dayDiff = diffInDays(startDate, targetDate);
    return dayDiff >= 0 && dayDiff % recurrenceEvery === 0;
  }

  if (recurrenceUnit === 'weeks') {
    const dayDiff = diffInDays(startDate, targetDate);
    const cycleDays = recurrenceEvery * 7;
    return dayDiff >= 0 && dayDiff % cycleDays === 0;
  }

  const monthDiff = diffInMonths(startDate, targetDate);
  if (monthDiff < 0 || monthDiff % recurrenceEvery !== 0) {
    return false;
  }
  const scheduledDay = Math.min(
      startDate.day,
      getDaysInMonth(targetDate.year, targetDate.month),
  );
  return targetDate.day === scheduledDay;
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
      tasks.push(compactUndefined({
        id: buildTaskId('procedure', procedure.id, entry.time, index),
        type: 'procedure',
        procedureId: procedure.id,
        title: `Procedure: ${name}`,
        required: true,
        scheduledTime: entry.time,
        notes: instructions,
      }) as unknown as Task);
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
      tasks.push(compactUndefined({
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
      }) as unknown as Task);
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
      tasks.push(compactUndefined({
        id: buildTaskId('insulin_basal', profile.id, entry.time, index),
        type: 'insulin_basal',
        insulinProfileId: profile.id,
        title: `Insulin (Basal): ${label}`,
        required: true,
        scheduledTime: entry.time,
        plannedUnits,
        notes: readString(profile.notes) ?? 'Fixed basal dose.',
      }) as unknown as Task);
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

function parseDateId(value: string | undefined): DateParts | null {
  if (!value) {
    return null;
  }
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) {
    return null;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)) {
    return null;
  }
  if (month < 1 || month > 12) {
    return null;
  }

  const maxDay = getDaysInMonth(year, month);
  if (day < 1 || day > maxDay) {
    return null;
  }

  return {year, month, day};
}

function getDaysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function compareDateParts(left: DateParts, right: DateParts): number {
  if (left.year !== right.year) {
    return left.year - right.year;
  }
  if (left.month !== right.month) {
    return left.month - right.month;
  }
  return left.day - right.day;
}

function toUtcDate(date: DateParts): Date {
  return new Date(Date.UTC(date.year, date.month - 1, date.day));
}

function diffInDays(start: DateParts, end: DateParts): number {
  const millisPerDay = 24 * 60 * 60 * 1000;
  return Math.floor((toUtcDate(end).getTime() - toUtcDate(start).getTime()) / millisPerDay);
}

function diffInMonths(start: DateParts, end: DateParts): number {
  return (end.year - start.year) * 12 + (end.month - start.month);
}

function readPositiveInteger(value: unknown): number | undefined {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return undefined;
  }
  if (!Number.isInteger(value) || value < 1) {
    return undefined;
  }
  return value;
}

function normalizeRecurrenceUnit(value: string | undefined): 'days' | 'weeks' | 'months' | undefined {
  switch (value?.toLowerCase()) {
    case 'day':
    case 'days':
      return 'days';
    case 'week':
    case 'weeks':
      return 'weeks';
    case 'month':
    case 'months':
      return 'months';
    default:
      return undefined;
  }
}

function compactUndefined<T extends Record<string, unknown>>(record: T): T {
  const output: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(record)) {
    if (value !== undefined) {
      output[key] = value;
    }
  }
  return output as T;
}
