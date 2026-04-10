import test from 'node:test';
import assert from 'node:assert/strict';
import {generateChecklistTasks} from '../lib/checklistGenerator';

const baseInput = {
  patientId: 'patient-1',
  procedures: [],
  insulinProfiles: [],
};

test('medicine with daily recurrence is scheduled every day', () => {
  const tasks = generateChecklistTasks({
    ...baseInput,
    dateId: '2026-04-10',
    medicines: [
      {
        id: 'med-1',
        name: 'Vitamin D',
        active: true,
        scheduleTimes: ['08:00'],
      },
    ],
  });

  assert.equal(tasks.length, 1);
  assert.equal(tasks[0]?.type, 'medicine');
});

test('medicine with interval recurrence schedules only on matching day cycles', () => {
  const medicine = {
    id: 'med-interval-days',
    name: 'Antibiotic',
    active: true,
    scheduleTimes: ['09:00'],
    startDate: '2026-04-01',
    recurrenceMode: 'interval',
    recurrenceEvery: 2,
    recurrenceUnit: 'days',
  };

  const scheduled = generateChecklistTasks({
    ...baseInput,
    dateId: '2026-04-03',
    medicines: [medicine],
  });
  const skipped = generateChecklistTasks({
    ...baseInput,
    dateId: '2026-04-04',
    medicines: [medicine],
  });

  assert.equal(scheduled.length, 1);
  assert.equal(skipped.length, 0);
});

test('monthly interval recurrence clamps to month end when needed', () => {
  const medicine = {
    id: 'med-interval-months',
    name: 'Injection',
    active: true,
    scheduleTimes: ['10:00'],
    startDate: '2026-01-31',
    recurrenceMode: 'interval',
    recurrenceEvery: 1,
    recurrenceUnit: 'months',
  };

  const onMonthEnd = generateChecklistTasks({
    ...baseInput,
    dateId: '2026-02-28',
    medicines: [medicine],
  });
  const nonMatchingDay = generateChecklistTasks({
    ...baseInput,
    dateId: '2026-02-27',
    medicines: [medicine],
  });

  assert.equal(onMonthEnd.length, 1);
  assert.equal(nonMatchingDay.length, 0);
});
