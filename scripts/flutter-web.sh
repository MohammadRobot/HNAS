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

cd "$APP_DIR"

COMMON_ARGS=(
  "--dart-define=HNAS_API_BASE_URL=$API_BASE_URL"
  "--dart-define=HNAS_FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID"
  "--dart-define=HNAS_USE_FIREBASE_EMULATORS=$USE_FIREBASE_EMULATORS"
  "--dart-define=HNAS_EMULATOR_HOST=$EMULATOR_HOST"
  "--dart-define=HNAS_FIRESTORE_EMULATOR_PORT=$FIRESTORE_EMULATOR_PORT"
  "--dart-define=HNAS_AUTH_EMULATOR_PORT=$AUTH_EMULATOR_PORT"
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
