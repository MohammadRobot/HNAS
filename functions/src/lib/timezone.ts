const DEFAULT_TIME_ZONE = 'Etc/UTC';

interface ZonedDateParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
}

export function normalizeTimeZone(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return DEFAULT_TIME_ZONE;
  }

  const candidate = value.trim();
  try {
    // Throws RangeError for unknown time zone identifiers.
    new Intl.DateTimeFormat('en-US', {timeZone: candidate});
    return candidate;
  } catch {
    return DEFAULT_TIME_ZONE;
  }
}

export function getDateIdForTimeZone(date: Date, timeZone: string): string {
  const zoned = getZonedDateParts(date, timeZone);
  return `${zoned.year}-${String(zoned.month).padStart(2, '0')}-${String(zoned.day).padStart(2, '0')}`;
}

export function shouldGenerateChecklistNow(
    date: Date,
    timeZone: string,
    generationWindowMinutes = 15,
): boolean {
  const zoned = getZonedDateParts(date, timeZone);
  return zoned.hour === 0 && zoned.minute >= 0 && zoned.minute < generationWindowMinutes;
}

export function shouldRunEndOfDaySweepNow(
    date: Date,
    timeZone: string,
    sweepStartMinute = 45,
): boolean {
  const zoned = getZonedDateParts(date, timeZone);
  return zoned.hour === 23 && zoned.minute >= sweepStartMinute && zoned.minute <= 59;
}

export function getZonedDateParts(date: Date, timeZone: string): ZonedDateParts {
  const normalizedTimeZone = normalizeTimeZone(timeZone);
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: normalizedTimeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  });
  const parts = formatter.formatToParts(date);

  const year = readPart(parts, 'year');
  const month = readPart(parts, 'month');
  const day = readPart(parts, 'day');
  const hour = readPart(parts, 'hour');
  const minute = readPart(parts, 'minute');

  return {year, month, day, hour, minute};
}

function readPart(
    parts: Intl.DateTimeFormatPart[],
    type: Intl.DateTimeFormatPartTypes,
): number {
  const part = parts.find((candidate) => candidate.type === type);
  if (!part) {
    throw new Error(`Unable to read "${type}" from date parts.`);
  }

  const parsed = Number(part.value);
  if (!Number.isInteger(parsed)) {
    throw new Error(`Invalid "${type}" value "${part.value}".`);
  }
  return parsed;
}
