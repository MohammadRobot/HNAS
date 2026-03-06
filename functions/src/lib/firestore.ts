import { getApps, initializeApp } from 'firebase-admin/app';
import {
  type CollectionReference,
  type DocumentData,
  getFirestore,
  Timestamp,
} from 'firebase-admin/firestore';

const app = getApps().length > 0 ? getApps()[0] : initializeApp();

export const firestore = getFirestore(app);

export function patientSubcollectionRef<T extends DocumentData = DocumentData>(
  patientId: string,
  subcollectionName: string,
): CollectionReference<T> {
  return firestore.collection('patients').doc(patientId).collection(subcollectionName) as CollectionReference<T>;
}

export type DateIdInput = Date | Timestamp | string | number;

export function toDateId(input: DateIdInput = new Date()): string {
  const date = normalizeDate(input);
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function normalizeDate(input: DateIdInput): Date {
  if (input instanceof Date) {
    return input;
  }

  if (input instanceof Timestamp) {
    return input.toDate();
  }

  return new Date(input);
}

