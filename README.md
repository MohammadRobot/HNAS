# HNAS Monorepo

This repository contains:

- `apps/flutter_app/` - Flutter app (Riverpod + go_router) with login, dashboard, patient tabs, checklist, reports, and AI assistant UI.
- `functions/` - Firebase Cloud Functions (TypeScript) API, jobs, triggers, and shared libs.
- Firebase project config for Firestore, Functions, and Hosting.

## Setup

1. Install Firebase CLI:
   ```bash
   npm install -g firebase-tools
   ```
2. Install Flutter app dependencies:
   ```bash
   cd apps/flutter_app
   flutter pub get
   cd ../..
   ```
3. Install Cloud Functions dependencies:
   ```bash
   cd functions
   npm install
   cd ..
   ```
4. Start local emulators:
   ```bash
   firebase emulators:start
   ```
5. Deploy:
   ```bash
   firebase deploy
   ```

## Run Flutter Web With API URL

Set the HTTPS function base URL via `--dart-define`:

```bash
cd apps/flutter_app
flutter run -d chrome --dart-define=HNAS_API_BASE_URL=https://us-central1-<project-id>.cloudfunctions.net/api
```

For emulator testing, use your local function URL as the base value.

## Seed Data (MVP)

Create three Firebase Auth users (email/password):

- admin user
- supervisor user
- nurse user

Get each UID, then create matching Firestore user profiles in `/users/{uid}`:

```json
// /users/<admin_uid>
{
  "role": "admin",
  "agencyId": "agency_demo_1",
  "displayName": "Admin One"
}
```

```json
// /users/<supervisor_uid>
{
  "role": "supervisor",
  "agencyId": "agency_demo_1",
  "displayName": "Supervisor One"
}
```

```json
// /users/<nurse_uid>
{
  "role": "nurse",
  "agencyId": "agency_demo_1",
  "displayName": "Nurse One"
}
```

Create one diabetic patient document in `/patients/{patientId}`:

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

Create one procedure template in `/procedureTemplates/{templateId}`:

```json
{
  "name": "Blood Pressure Check",
  "instructions": "Measure and record blood pressure.",
  "frequency": "daily",
  "active": true
}
```

Hosting serves Flutter web output from `apps/flutter_app/build/web`.
