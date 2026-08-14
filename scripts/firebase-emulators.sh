#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if [[ -z "${JAVA_HOME:-}" ]]; then
  for jdk_home in \
    /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
    /usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
    "$HOME/.local/jdks/temurin-21.0.8"; do
    if [[ -x "$jdk_home/bin/java" ]]; then
      export JAVA_HOME="$jdk_home"
      break
    fi
  done
fi

if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
  export PATH="$JAVA_HOME/bin:$PATH"
fi

if ! java -version >/dev/null 2>&1; then
  echo "Java 21 is required. Install it with: brew install openjdk@21" >&2
  exit 1
fi

cd "$ROOT_DIR/functions"

for firebase_js in \
  /opt/homebrew/opt/firebase-cli/libexec/lib/node_modules/firebase-tools/lib/bin/firebase.js \
  /usr/local/opt/firebase-cli/libexec/lib/node_modules/firebase-tools/lib/bin/firebase.js; do
  if [[ -f "$firebase_js" && -x /opt/homebrew/opt/node@22/bin/node ]]; then
    exec /opt/homebrew/opt/node@22/bin/node "$firebase_js" emulators:start \
      --config ../firebase.json \
      --project demo-hnas \
      --only auth,firestore,functions
  fi
  if [[ -f "$firebase_js" && -x /usr/local/opt/node@22/bin/node ]]; then
    exec /usr/local/opt/node@22/bin/node "$firebase_js" emulators:start \
      --config ../firebase.json \
      --project demo-hnas \
      --only auth,firestore,functions
  fi
done

if command -v firebase >/dev/null 2>&1; then
  exec firebase emulators:start \
    --config ../firebase.json \
    --project demo-hnas \
    --only auth,firestore,functions
fi

exec npx --yes firebase-tools emulators:start \
  --config ../firebase.json \
  --project demo-hnas \
  --only auth,firestore,functions
