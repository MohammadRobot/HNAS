import assert from 'node:assert/strict';
import test from 'node:test';
import {findVisitStartTime, summarizeVisitProgress} from '../lib/visits';
import {type Task} from '../lib/types';

const tasks = [
  {
    id: 'morning_medicine',
    type: 'medicine',
    title: 'Morning medicine',
    required: true,
    scheduledTime: '09:00',
    medicineId: 'medicine_1',
  },
  {
    id: 'blood_pressure',
    type: 'health_check',
    title: 'Blood pressure',
    required: true,
    scheduledTime: '08:30',
    healthCheckPlanId: 'plan_1',
  },
] as Task[];

test('summarizeVisitProgress selects the first unresolved checklist task', () => {
  const summary = summarizeVisitProgress(tasks, [
    {taskId: 'morning_medicine', status: 'done'},
  ]);

  assert.deepEqual(summary, {
    taskCount: 2,
    completedTaskCount: 1,
    pendingTaskCount: 1,
    issueCount: 0,
    currentTaskId: 'blood_pressure',
  });
});

test('summarizeVisitProgress counts structured non-routine outcomes', () => {
  const summary = summarizeVisitProgress(tasks, [
    {
      taskId: 'morning_medicine',
      status: 'skipped',
      inputs: {outcomeReason: 'patient_declined'},
    },
    {
      taskId: 'blood_pressure',
      status: 'failed',
      inputs: {outcomeReason: 'needs_help'},
    },
  ]);

  assert.equal(summary.completedTaskCount, 2);
  assert.equal(summary.pendingTaskCount, 0);
  assert.equal(summary.issueCount, 2);
  assert.equal(summary.currentTaskId, undefined);
});

test('findVisitStartTime returns the earliest scheduled task', () => {
  assert.equal(findVisitStartTime(tasks), '08:30');
  assert.equal(findVisitStartTime([]), undefined);
});
