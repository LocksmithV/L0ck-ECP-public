#!/usr/bin/env bash
# Smoke test: build the debug APK and fail loudly with a clear signal if it
# didn't actually produce one, instead of relying on parsing Gradle's output.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build apk --debug 2>&1 | tee build.log

APK="build/app/outputs/flutter-apk/app-debug.apk"
if [ ! -f "$APK" ]; then
  echo "APK not built! ($APK missing — see build.log)" >&2
  exit 1
fi

echo "OK: $APK"
