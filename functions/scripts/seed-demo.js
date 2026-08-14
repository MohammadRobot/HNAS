/* eslint-disable no-console */
const admin = require('firebase-admin');

const projectId = process.env.HNAS_PROJECT_ID || 'demo-hnas';
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || projectId;

admin.initializeApp({ projectId });
const db = admin.firestore();

async function ensureUser(email, password, displayName) {
  try {
    return await admin.auth().getUserByEmail(email);
  } catch (error) {
    if (error && error.code === 'auth/user-not-found') {
      return admin.auth().createUser({ email, password, displayName });
    }
    throw error;
  }
}

async function main() {
  const adminUser = await ensureUser('admin@hnas.local', 'Passw0rd!', 'Admin One');
  const nurseUser = await ensureUser('nurse@hnas.local', 'Passw0rd!', 'Nurse One');
  const patientUser = await ensureUser(
    'patient@hnas.local',
    'Passw0rd!',
    'Demo Patient',
  );
  const relativeUser = await ensureUser(
    'relative@hnas.local',
    'Passw0rd!',
    'Demo Relative',
  );

  await db.collection('users').doc(adminUser.uid).set(
    {
      role: 'admin',
      agencyId: 'agency_demo_1',
      displayName: 'Admin One',
    },
    { merge: true },
  );

  await db.collection('users').doc(nurseUser.uid).set(
    {
      role: 'nurse',
      agencyId: 'agency_demo_1',
      displayName: 'Nurse One',
    },
    { merge: true },
  );

  await db.collection('users').doc(patientUser.uid).set(
    {
      role: 'patient',
      agencyId: 'agency_demo_1',
      displayName: 'Demo Patient',
      patientId: 'patient_demo_1',
    },
    { merge: true },
  );

  await db.collection('users').doc(relativeUser.uid).set(
    {
      role: 'relative',
      agencyId: 'agency_demo_1',
      displayName: 'Demo Relative',
      patientIds: ['patient_demo_1'],
    },
    { merge: true },
  );

  await db.collection('patients').doc('patient_demo_1').set(
    {
      id: 'patient_demo_1',
      fullName: 'Demo Diabetic Patient',
      active: true,
      timezone: 'Etc/UTC',
      agencyId: 'agency_demo_1',
      assignedNurseIds: [nurseUser.uid],
      riskFlags: ['diabetes'],
      diagnosis: ['Type 2 Diabetes'],
      allergies: ['Penicillin'],
    },
    { merge: true },
  );

  await db
    .collection('patients')
    .doc('patient_demo_1')
    .collection('insulinProfiles')
    .doc('humalog_rapid')
    .set(
      {
        id: 'humalog_rapid',
        type: 'rapid',
        label: 'Humalog',
        insulinName: 'Humalog',
        active: true,
        slidingScaleMgdl: [150, 200, 250],
        mealBaseUnits: {
          breakfast: 4,
          lunch: 5,
          dinner: 6,
          snack: 2,
          none: 0,
        },
        defaultBaseUnits: 4,
        schedule: {
          times: ['08:00', '12:00', '18:00'],
        },
      },
      { merge: true },
    );

  const patientRef = db.collection('patients').doc('patient_demo_1');

  await patientRef.collection('medicines').doc('metformin_morning').set(
    {
      id: 'metformin_morning',
      name: 'Metformin',
      active: true,
      doseAmount: 500,
      doseUnit: 'mg',
      instructions: 'Confirm the documented dose and offer with breakfast.',
      scheduleTimes: ['09:00'],
      recurrenceMode: 'daily',
    },
    { merge: true },
  );

  await patientRef.collection('procedures').doc('mobility_support').set(
    {
      id: 'mobility_support',
      name: 'Supported mobility walk',
      active: true,
      instructions:
        'Use the documented mobility aid and stop if the patient feels unsteady.',
      frequency: 'daily',
      scheduleTimes: ['10:00'],
    },
    { merge: true },
  );

  await patientRef.collection('healthCheckPlans').doc('bp_daily').set(
    {
      id: 'bp_daily',
      label: 'Morning blood pressure',
      itemType: 'blood_pressure',
      timing: 'before_food',
      active: true,
      notes: 'Measure while seated after a short rest and record the reading.',
    },
    { merge: true },
  );

  const dateId = new Date().toISOString().slice(0, 10);
  const checklistRef = patientRef.collection('dailyChecklists').doc(dateId);
  const checklistSnapshot = await checklistRef.get();
  const existingChecklist = checklistSnapshot.exists
    ? checklistSnapshot.data() || {}
    : {};
  const tasks = [
    {
      id: `health_check_bp_daily_${dateId}_08_30`,
      type: 'health_check',
      title: 'Morning blood pressure',
      required: true,
      scheduledTime: '08:30',
      notes: 'Measure while seated after a short rest and record the reading.',
      healthCheckPlanId: 'bp_daily',
      itemType: 'blood_pressure',
      timing: 'before_food',
    },
    {
      id: `medicine_metformin_morning_${dateId}_09_00`,
      type: 'medicine',
      title: 'Metformin 500 mg',
      required: true,
      scheduledTime: '09:00',
      notes: 'Confirm the documented dose and offer with breakfast.',
      medicineId: 'metformin_morning',
      plannedDoseAmount: 500,
      plannedDoseUnit: 'mg',
    },
    {
      id: `procedure_mobility_support_${dateId}_10_00`,
      type: 'procedure',
      title: 'Supported mobility walk',
      required: true,
      scheduledTime: '10:00',
      notes:
        'Use the documented mobility aid and stop if the patient feels unsteady.',
      procedureId: 'mobility_support',
    },
    {
      id: `insulin_rapid_humalog_rapid_${dateId}_12_00`,
      type: 'insulin_rapid',
      title: 'Humalog rapid insulin',
      required: true,
      scheduledTime: '12:00',
      notes:
        'Record glucose and meal context. Follow the approved care plan and escalation rules.',
      insulinProfileId: 'humalog_rapid',
    },
  ];
  const taskIds = new Set(tasks.map((task) => task.id));
  const existingResults = Array.isArray(existingChecklist.results)
    ? existingChecklist.results.filter((result) => taskIds.has(result.taskId))
    : [];
  const nowIso = new Date().toISOString();
  await checklistRef.set(
    {
      id: dateId,
      patientId: 'patient_demo_1',
      dateId,
      tasks,
      results: existingResults,
      issues: Array.isArray(existingChecklist.issues)
        ? existingChecklist.issues
        : [],
      createdAt: existingChecklist.createdAt || nowIso,
      updatedAt: nowIso,
    },
    { merge: false },
  );

  await db
    .collection('patients')
    .doc('patient_demo_1')
    .collection('insulinProfiles')
    .doc('tresiba_basal')
    .set(
      {
        id: 'tresiba_basal',
        type: 'basal',
        label: 'Tresiba',
        insulinName: 'Tresiba',
        active: true,
        fixedUnits: 18,
        schedule: {
          time: '21:00',
        },
      },
      { merge: true },
    );

  await db.collection('procedureTemplates').doc('bp_daily').set(
    {
      name: 'Blood Pressure Check',
      instructions: 'Measure and record blood pressure.',
      frequency: 'daily',
      active: true,
    },
    { merge: true },
  );

  console.log('SEEDED_OK');
  console.log(`PROJECT_ID=${projectId}`);
  console.log('ADMIN_EMAIL=admin@hnas.local');
  console.log('NURSE_EMAIL=nurse@hnas.local');
  console.log('PATIENT_EMAIL=patient@hnas.local');
  console.log('RELATIVE_EMAIL=relative@hnas.local');
  console.log('PASSWORD=Passw0rd!');
}

main().catch((error) => {
  console.error('SEED_FAILED');
  console.error(error);
  process.exitCode = 1;
});
