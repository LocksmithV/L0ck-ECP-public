#!/usr/bin/env bash
# Puts SimpleX Chat's core (libsimplex.so, AGPLv3) into the app, taken from the official,
# reproducibly built release APK. The library is ~190 MB, so it is not in git.
#   SIMPLEX_DL  download cache (default ~/.l0ck-ecp-toolchain/dl/simplex-$VERSION)
set -euo pipefail
VERSION=v7.0.3
# SHA2-256 of simplex-aarch64.apk as published in the release notes and signed by the
# SimpleX build key BBDF 7BDA D154 8B16 836A F5B9 D53B DFD1 53C3 66BA
APK_SHA256=d535e5a8986d4e11b9abd5656a3c0e1be5a08e06b00a7b20d6b7587ed0c3457f

here=$(cd "$(dirname "$0")" && pwd)
dl=${SIMPLEX_DL:-$HOME/.l0ck-ecp-toolchain/dl/simplex-$VERSION}
out="$here/../app/src/main/jniLibs/arm64-v8a"
mkdir -p "$dl" "$out"
apk="$dl/simplex-aarch64.apk"
if [ ! -f "$apk" ]; then
  curl -sSfL -o "$apk" "https://github.com/simplex-chat/simplex-chat/releases/download/$VERSION/simplex-aarch64.apk"
fi
echo "$APK_SHA256  $apk" | sha256sum -c -
unzip -o -j -q "$apk" lib/arm64-v8a/libsimplex.so -d "$out"
ls -la "$out/libsimplex.so"
