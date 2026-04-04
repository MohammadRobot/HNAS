/* eslint-disable no-console */
const admin = require('firebase-admin');

const projectId = process.env.HNAS_PROJECT_ID || process.env.GCLOUD_PROJECT || 'demo-hnas';
const dryRun = String(process.env.DRY_RUN || '').toLowerCase() === 'true';

if (!admin.apps.length) {
  admin.initializeApp({projectId});
}

const db = admin.firestore();
const {FieldValue} = admin.firestore;

function normalizeProfiles(rawProfiles) {
  if (!Array.isArray(rawProfiles)) {
    return [];
  }

  const map = new Map();
  rawProfiles.forEach((value, index) => {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      return;
    }

    const profile = {...value};
    const id = typeof profile.id === 'string' && profile.id.trim().length > 0 ?
      profile.id.trim() :
      `inline_${index + 1}`;
    const type = typeof profile.type === 'string' ? profile.type.trim().toLowerCase() : 'rapid';
    if (type !== 'rapid' && type !== 'basal') {
      return;
    }

    profile.id = id;
    profile.type = type;
    if (typeof profile.active !== 'boolean') {
      profile.active = true;
    }

    map.set(id, profile);
  });

  return Array.from(map.values());
}

async function main() {
  const patientsSnap = await db.collection('patients').get();
  let scannedPatients = 0;
  let touchedPatients = 0;
  let migratedProfiles = 0;

  for (const patientDoc of patientsSnap.docs) {
    scannedPatients += 1;
    const patientData = patientDoc.data() || {};
    const normalizedProfiles = normalizeProfiles(patientData.insulinProfiles);
    if (normalizedProfiles.length === 0) {
      continue;
    }

    touchedPatients += 1;
    const nowIso = new Date().toISOString();
    const batch = db.batch();

    for (const profile of normalizedProfiles) {
      const profileRef = patientDoc.ref.collection('insulinProfiles').doc(profile.id);
      batch.set(profileRef, {
        ...profile,
        id: profile.id,
        updatedAt: nowIso,
        createdAt: typeof profile.createdAt === 'string' ? profile.createdAt : nowIso,
      }, {merge: true});
      migratedProfiles += 1;
    }

    batch.set(patientDoc.ref, {
      insulinProfiles: FieldValue.delete(),
      updatedAt: nowIso,
    }, {merge: true});

    if (!dryRun) {
      await batch.commit();
    }
  }

  console.log('MIGRATION_COMPLETE');
  console.log(`PROJECT_ID=${projectId}`);
  console.log(`DRY_RUN=${dryRun}`);
  console.log(`SCANNED_PATIENTS=${scannedPatients}`);
  console.log(`TOUCHED_PATIENTS=${touchedPatients}`);
  console.log(`MIGRATED_PROFILES=${migratedProfiles}`);
}

main().catch((error) => {
  console.error('MIGRATION_FAILED');
  console.error(error);
  process.exitCode = 1;
});
