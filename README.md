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

- Firebase Auth login for staff users (Email/Password + Google on web)
- role-aware patient access for admins, supervisors, and nurses
- dashboard with patient list and same-day counts
- patient details with tabs for overview, medications, procedures, lab tests, checklist, reports, and AI assistant
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
- Node.js 22 and npm
- Firebase CLI

If you use `nvm`, this repository includes a `.nvmrc` pinned to Node 22:

```bash
nvm install
nvm use
```

### Firebase Setup Step By Step

If you do not already have Firebase configured, follow these steps first.

#### 1. Create A Firebase Account

- go to the Firebase Console
- sign in with your Google account
- if this is your first time, complete the initial Firebase onboarding

Firebase Console:
`https://console.firebase.google.com`

#### 2. Create A Firebase Project

- click `Create a project`
- enter a project name
- choose whether to enable Google Analytics
- finish project creation

Keep the Firebase `projectId` because you will use it in CLI commands and local URLs.

#### 3. Enable Firebase Authentication

- open your Firebase project
- go to `Build` -> `Authentication`
- click `Get started`
- enable the `Email/Password` sign-in provider
- enable the `Google` sign-in provider if you want Google login on the web app

This project uses Firebase Auth for staff login.

#### 4. Create A Firestore Database

- go to `Build` -> `Firestore Database`
- click `Create database`
- choose a database location
- create the database

Choose the location carefully because Firestore location cannot be changed later.

#### 5. Register Your Flutter App In Firebase

This repository currently contains the Flutter source code but not generated platform folders or Firebase app config.

First generate the Flutter platform scaffolding:

```bash
cd apps/flutter_app
flutter create .
```

Then register the app with Firebase. At minimum, register the `Web` app if you plan to run with `flutter run -d chrome`.

#### 6. Install And Log In To Firebase CLI

Install the CLI if you have not already:

```bash
npm install -g firebase-tools
```

Log in:

```bash
firebase login
```

#### 7. Link This Repository To Your Firebase Project

From the repository root:

```bash
cd ~/HNAS
firebase use --add
```

Select the Firebase project you created in step 2.

#### 8. Configure FlutterFire

Generate Firebase config for the Flutter app:

```bash
dart pub global activate flutterfire_cli
cd apps/flutter_app
flutterfire configure --project <your-project-id>
```

Select the platforms you want to support. For this repository, `web` is the minimum useful choice.

#### 9. Install Project Dependencies

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

#### 10. Start The Project

Start Firebase emulators:

```bash
firebase emulators:start
```

In another terminal, run Flutter web:

```bash
cd apps/flutter_app
flutter run -d chrome --dart-define=HNAS_API_BASE_URL=http://127.0.0.1:5001/<project-id>/us-central1/api
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
cd ~/HNAS
npm run build:flutter:web
```

Firebase Hosting is configured to serve the Flutter web build output from `apps/flutter_app/build/web`.

### Environment File Setup

The repository includes:

- `.env.example` as a template
- `.env` for local values (git-ignored)

Create/update your local env file:

```bash
cd ~/HNAS
cp -n .env.example .env
```

NPM scripts now auto-load `.env` by default (via `scripts/with-env.sh`), so
you usually do not need to manually source the file.

`npm run build:flutter:web` also injects these web Firebase values from `.env`
into `--dart-define` at build time:

- `HNAS_FIREBASE_API_KEY`
- `HNAS_FIREBASE_APP_ID`
- `HNAS_FIREBASE_MESSAGING_SENDER_ID`
- `HNAS_FIREBASE_PROJECT_ID`
- `HNAS_API_BASE_URL`

If you run commands directly (outside npm scripts), load env values into your
current shell:

```bash
cd ~/HNAS
set -a
source .env
set +a
```

### Known-Good Local Run (Verified March 13, 2026)

The sequence below was validated end-to-end on this repository.

Terminal A: start emulators

```bash
cd ~/HNAS
npm run serve:functions
```

Terminal B: seed demo users and patient data

```bash
cd ~/HNAS
npm --prefix functions run seed:demo
```

Terminal C: run Flutter web app against emulators

```bash
cd ~/HNAS
npm run run:flutter:web
```

Optional: pass extra Flutter args:

```bash
npm run run:flutter:web -- --web-port 5050
```

Optional: enable ChatGPT-backed responses in the AI tab (Terminal A before
`npm run serve:functions`):

```bash
export AI_MODEL_PROVIDER=openai
export OPENAI_API_KEY=<your-openai-api-key>
export OPENAI_MODEL=gpt-4o-mini
# optional override, default is chat completions endpoint:
# export OPENAI_ENDPOINT=https://api.openai.com/v1/chat/completions
```

If OpenAI config is not set, the backend uses template/deterministic fallback
responses.

## Production Checklist (Verified April 4, 2026)

1. Set production values in `.env`:
```bash
HNAS_API_BASE_URL=https://us-central1-<project-id>.cloudfunctions.net/api
HNAS_FIREBASE_PROJECT_ID=<project-id>
HNAS_USE_FIREBASE_EMULATORS=false
HNAS_FIREBASE_API_KEY=<web-api-key>
HNAS_FIREBASE_APP_ID=<web-app-id>
HNAS_FIREBASE_MESSAGING_SENDER_ID=<sender-id>
```
2. Run deployment commands together:
```bash
cd ~/HNAS

# 1) Select correct Firebase project
firebase login
firebase use --add
firebase use hnas-4a4b8

# 2) Build web app (uses .env values)
npm run build:flutter:web

# 3) Deploy backend + rules + hosting
firebase deploy --only hosting,functions,firestore:rules,firestore:indexes

# If first deploy fails only on Firestore trigger setup, run once more:
firebase deploy --only functions:onTaskUpdate
```
3. Create staff users in Firebase Auth and create matching Firestore user docs:
`/users/{uid}` with `role`, `agencyId`, and `displayName`.
4. Patient visibility rules:
- `admin` and `supervisor` can read patients in the same `agencyId`
- `nurse` can read only patients where their uid is in `assignedNurseIds`
5. If dashboard shows `permission-denied`, verify:
- `/users/{uid}` exists for the signed-in account
- user `role` is `admin`, `supervisor`, or `nurse`
- patient `agencyId` and/or `assignedNurseIds` are set correctly

Demo login credentials:

- `admin@hnas.local` / `Passw0rd!`
- `nurse@hnas.local` / `Passw0rd!`

Optional API smoke check:

```bash
TOKEN=$(curl -sS -X POST 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-api-key' \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@hnas.local","password":"Passw0rd!","returnSecureToken":true}' \
  | node -pe "JSON.parse(require('fs').readFileSync(0,'utf8')).idToken")

curl -sS -X POST 'http://127.0.0.1:5001/demo-hnas/us-central1/api/api/ai/ask' \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"patientId":"patient_demo_1","question":"What tasks should I do today?"}'
```

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

If only the Firestore trigger deployment fails during initial 2nd gen setup,
retry just that function:

```bash
firebase deploy --only functions:onTaskUpdate
```

## Notes

- `firebase.json` points Functions to the `functions/` directory
- Firestore rules and indexes are configured at the repository root
- Hosting serves the Flutter web build output
- business-specific clinical logic should remain on the backend, not in the client
