#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
shift || true

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/flutter_app"

API_BASE_URL="${HNAS_API_BASE_URL:-http://127.0.0.1:5001/demo-hnas/us-central1/api}"
FIREBASE_PROJECT_ID="${HNAS_FIREBASE_PROJECT_ID:-demo-hnas}"
USE_FIREBASE_EMULATORS="${HNAS_USE_FIREBASE_EMULATORS:-true}"
EMULATOR_HOST="${HNAS_EMULATOR_HOST:-127.0.0.1}"
FIRESTORE_EMULATOR_PORT="${HNAS_FIRESTORE_EMULATOR_PORT:-8080}"
AUTH_EMULATOR_PORT="${HNAS_AUTH_EMULATOR_PORT:-9099}"
FIREBASE_API_KEY="${HNAS_FIREBASE_API_KEY:-demo-api-key}"
FIREBASE_APP_ID="${HNAS_FIREBASE_APP_ID:-1:1234567890:web:demohnas}"
FIREBASE_MESSAGING_SENDER_ID="${HNAS_FIREBASE_MESSAGING_SENDER_ID:-1234567890}"

cd "$APP_DIR"

COMMON_ARGS=(
  "--dart-define=HNAS_API_BASE_URL=$API_BASE_URL"
  "--dart-define=HNAS_FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID"
  "--dart-define=HNAS_USE_FIREBASE_EMULATORS=$USE_FIREBASE_EMULATORS"
  "--dart-define=HNAS_EMULATOR_HOST=$EMULATOR_HOST"
  "--dart-define=HNAS_FIRESTORE_EMULATOR_PORT=$FIRESTORE_EMULATOR_PORT"
  "--dart-define=HNAS_AUTH_EMULATOR_PORT=$AUTH_EMULATOR_PORT"
  "--dart-define=HNAS_FIREBASE_API_KEY=$FIREBASE_API_KEY"
  "--dart-define=HNAS_FIREBASE_APP_ID=$FIREBASE_APP_ID"
  "--dart-define=HNAS_FIREBASE_MESSAGING_SENDER_ID=$FIREBASE_MESSAGING_SENDER_ID"
)

case "$MODE" in
  run)
    exec flutter run -d chrome "${COMMON_ARGS[@]}" "$@"
    ;;
  build)
    exec flutter build web "${COMMON_ARGS[@]}" "$@"
    ;;
  *)
    echo "Usage: $0 [run|build] [extra flutter args...]" >&2
    exit 1
    ;;
esac
