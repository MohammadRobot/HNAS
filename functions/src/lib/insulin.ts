import { type InsulinProfileRapid } from './types';

const LOW_GLUCOSE_MGDL = 70;
const HIGH_GLUCOSE_MGDL = 250;

type KnownMealTag = 'breakfast' | 'lunch' | 'dinner' | 'snack' | 'none';

export interface RapidDoseProfile extends InsulinProfileRapid {
  slidingScaleMgdl?: number[];
  mealBaseUnits?: Partial<Record<KnownMealTag, number>>;
  defaultBaseUnits?: number;
}

export interface RapidDoseBreakdown {
  base: number;
  sliding: number;
  total: number;
}

export function computeSlidingScale(
  glucoseMgdl: number,
  slidingScaleMgdl: number[],
): number {
  if (!Number.isFinite(glucoseMgdl)) {
    return 0;
  }

  const thresholds = normalizeThresholds(slidingScaleMgdl);
  let units = 0;

  for (const threshold of thresholds) {
    if (glucoseMgdl >= threshold) {
      units += 1;
    }
  }

  return units;
}

export function computeRapidDose(
  mealTag: string,
  glucoseMgdl: number,
  rapidProfile: RapidDoseProfile,
): RapidDoseBreakdown {
  const normalizedMealTag = normalizeMealTag(mealTag);
  const base = resolveMealBaseDose(normalizedMealTag, rapidProfile);
  const sliding = computeSlidingScale(
    glucoseMgdl,
    Array.isArray(rapidProfile.slidingScaleMgdl) ? rapidProfile.slidingScaleMgdl : [],
  );
  const total = roundToTwo(base + sliding);

  return { base, sliding, total };
}

export function applySafetyFlags(glucoseMgdl: number): {low: boolean; high: boolean} {
  if (!Number.isFinite(glucoseMgdl)) {
    return { low: false, high: false };
  }

  return {
    low: glucoseMgdl < LOW_GLUCOSE_MGDL,
    high: glucoseMgdl >= HIGH_GLUCOSE_MGDL,
  };
}

function normalizeThresholds(slidingScaleMgdl: number[]): number[] {
  const unique = new Set<number>();
  for (const value of slidingScaleMgdl) {
    if (!Number.isFinite(value)) {
      continue;
    }
    if (value < 0) {
      continue;
    }
    unique.add(Math.floor(value));
  }

  return Array.from(unique.values()).sort((left, right) => left - right);
}

function normalizeMealTag(mealTag: string): KnownMealTag {
  const value = mealTag.trim().toLowerCase();

  if (value === 'breakfast' || value === 'lunch' || value === 'dinner' || value === 'snack') {
    return value;
  }

  return 'none';
}

function resolveMealBaseDose(mealTag: KnownMealTag, profile: RapidDoseProfile): number {
  const directMealBase = profile.mealBaseUnits?.[mealTag];
  if (Number.isFinite(directMealBase)) {
    return roundToTwo(directMealBase as number);
  }

  if (Number.isFinite(profile.defaultBaseUnits)) {
    return roundToTwo(profile.defaultBaseUnits as number);
  }

  return 0;
}

function roundToTwo(value: number): number {
  return Math.round(value * 100) / 100;
}

