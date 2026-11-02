#!/usr/bin/env bash
# Builds Bramble (Briar's core) into a local Maven repository for the app's Android build.
#   BRIAR_SRC   upstream Briar checkout, tag release-1.5.24 (default ~/.l0ck-ecp-toolchain/src/briar)
#   BRAMBLE_M2  output repository (default ~/.l0ck-ecp-toolchain/m2)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=${BRIAR_SRC:-$HOME/.l0ck-ecp-toolchain/src/briar}
cd "$src"
./gradlew --init-script "$here/publish-bramble.gradle" -x test -x lint \
  :bramble-api:publish :bramble-core:publish :bramble-android:publish :bramble-java:publish
