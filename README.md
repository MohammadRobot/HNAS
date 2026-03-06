# HNAS

HNAS is a home nursing assistant system for managing patient care workflows. It is built for agency teams such as admins, supervisors, and nurses who need to coordinate patient care, generate daily task checklists, record care activity, review reports, and use a guarded AI assistant for operational support.

This repository is a Firebase-based monorepo that combines a Flutter client with a TypeScript backend.

## Overview

HNAS is centered around a daily care workflow:

- staff authenticate with Firebase Auth
- users only see patients they are allowed to access
- active patients receive a generated daily checklist
- nurses complete or skip tasks from the mobile or web app
- missed, late, or unsafe events are tracked as issues and logs
- daily reports summarize task activity
- an AI assistant answers operational questions while blocking diagnosis, prescribing, and dose-change requests

## Features

- Firebase Auth login for staff users
- role-aware patient access for admins, supervisors, and nurses
- dashboard with patient list and same-day counts
- patient details with tabs for overview, medicines, procedures, insulin, checklist, reports, and AI assistant
- deterministic rapid insulin preview logic in the Flutter app
- HTTPS API for task updates and AI requests
- Firestore streams for patient, checklist, and report reads
- scheduled checklist generation and end-of-day sweep jobs
- Firestore trigger logic for task logging, insulin calculations, and issue creation
- Firestore security rules for user, patient, subcollection, template, and AI QA access

## Architecture

### Flutter App

The app lives in `apps/flutter_app/` and uses:

- `flutter_riverpod` for state management
- `go_router` for navigation
- Firestore streams for read-heavy screens
- HTTPS Cloud Functions for writes and AI calls

The UI currently includes:

- login screen
- dashboard
- patient details workspace
- checklist task cards
- reports view
- AI assistant chat UI

### Firebase Functions

The backend lives in `functions/` and includes:

- Express-based HTTPS API
- authorization helpers for Firebase ID token verification and role checks
- shared TypeScript domain types
- insulin utilities and rules engine helpers
- scheduled jobs for daily checklist generation and end-of-day processing
- Firestore trigger logic for task updates

### Firestore

Firestore is the source of truth for:

- users
- patients
- patient subcollections such as medicines, procedures, insulin profiles, reports, issues, task logs, and AI QA logs
- daily checklists generated per patient and date
- procedure templates

## Repository Structure

```text
hnas/
  apps/
    flutter_app/
  functions/
    src/
      api/
      jobs/
      triggers/
      lib/
  firebase.json
  firestore.rules
  firestore.indexes.json
  README.md
```

## Tech Stack

- Flutter
- Firebase Auth
- Cloud Firestore
- Firebase Cloud Functions
- Firebase Hosting
- TypeScript
- Express

## Local Setup

### Prerequisites

Install these tools before starting:

- Flutter SDK
- Node.js and npm
- Firebase CLI

Install Firebase CLI:

```bash
npm install -g firebase-tools
```

### Install Dependencies

Install Flutter packages:

```bash
cd apps/flutter_app
flutter pub get
cd ../..
```

Install Functions packages:

```bash
cd functions
npm install
cd ..
```

## Running The Project

### Start Firebase Emulators

From the repository root:

```bash
firebase emulators:start
```

### Run Flutter Web Against Deployed Functions

```bash
cd apps/flutter_app
flutter run -d chrome --dart-define=HNAS_API_BASE_URL=https://us-central1-<project-id>.cloudfunctions.net/api
```

### Run Flutter Web Against Local Emulators

Use the local Functions emulator URL as the base API:

```bash
cd apps/flutter_app
flutter run -d chrome --dart-define=HNAS_API_BASE_URL=http://127.0.0.1:5001/<project-id>/us-central1/api
```

### Build Flutter Web

```bash
cd apps/flutter_app
flutter build web
```

Firebase Hosting is configured to serve the Flutter web build output from `apps/flutter_app/build/web`.

## Seed Data

Create three Firebase Auth users with email and password:

- one admin
- one supervisor
- one nurse

Get each Firebase Auth UID, then create matching Firestore documents in `/users/{uid}`.

### Admin User

```json
{
  "role": "admin",
  "agencyId": "agency_demo_1",
  "displayName": "Admin One"
}
```

### Supervisor User

```json
{
  "role": "supervisor",
  "agencyId": "agency_demo_1",
  "displayName": "Supervisor One"
}
```

### Nurse User

```json
{
  "role": "nurse",
  "agencyId": "agency_demo_1",
  "displayName": "Nurse One"
}
```

### Demo Patient

Create one diabetic patient in `/patients/{patientId}`:

```json
{
  "id": "patient_demo_1",
  "fullName": "Demo Diabetic Patient",
  "active": true,
  "timezone": "Etc/UTC",
  "agencyId": "agency_demo_1",
  "assignedNurseIds": ["<nurse_uid>"],
  "riskFlags": ["diabetes"],
  "diagnosis": ["Type 2 Diabetes"],
  "insulinProfiles": [
    {
      "id": "humalog_rapid",
      "type": "rapid",
      "label": "Humalog",
      "insulinName": "Humalog",
      "active": true,
      "slidingScaleMgdl": [150, 200, 250],
      "mealBaseUnits": {
        "breakfast": 4,
        "lunch": 5,
        "dinner": 6,
        "snack": 2
      },
      "defaultBaseUnits": 4,
      "schedule": {
        "times": ["08:00", "12:00", "18:00"]
      }
    },
    {
      "id": "tresiba_basal",
      "type": "basal",
      "label": "Tresiba",
      "insulinName": "Tresiba",
      "active": true,
      "fixedUnits": 18,
      "schedule": {
        "time": "21:00"
      }
    }
  ]
}
```

### Procedure Template

Create one procedure template in `/procedureTemplates/{templateId}`:

```json
{
  "name": "Blood Pressure Check",
  "instructions": "Measure and record blood pressure.",
  "frequency": "daily",
  "active": true
}
```

## Deployment

Deploy Functions, Firestore config, and Hosting from the repository root:

```bash
firebase deploy
```

## Notes

- `firebase.json` points Functions to the `functions/` directory
- Firestore rules and indexes are configured at the repository root
- Hosting serves the Flutter web build output
- business-specific clinical logic should remain on the backend, not in the client
