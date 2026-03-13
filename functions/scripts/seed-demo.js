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
  console.log('PASSWORD=Passw0rd!');
}

main().catch((error) => {
  console.error('SEED_FAILED');
  console.error(error);
  process.exitCode = 1;
});
