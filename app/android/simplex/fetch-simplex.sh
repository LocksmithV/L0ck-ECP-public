#!/usr/bin/env bash
# Puts SimpleX Chat's core (libsimplex.so, AGPLv3) into the app, taken from the official,
# reproducibly built release APK. The library is ~190 MB, so it is not in git.
#   SIMPLEX_DL  download cache (default ~/.l0ck-ecp-toolchain/dl/simplex-$VERSION)
set -euo pipefail
VERSION=v7.0.3
# SHA2-256 of the release APKs as published in the release notes and signed by the
# SimpleX build key BBDF 7BDA D154 8B16 836A F5B9 D53B DFD1 53C3 66BA. arm64 phones use the
# aarch64 APK's core, 32-bit ARM phones (armeabi-v7a) the armv7a one.
#   ./fetch-simplex.sh            arm64-v8a
#   ./fetch-simplex.sh armeabi-v7a
ABI=${1:-arm64-v8a}
case "$ABI" in
  arm64-v8a)   NAME=simplex-aarch64.apk APK_SHA256=d535e5a8986d4e11b9abd5656a3c0e1be5a08e06b00a7b20d6b7587ed0c3457f ;;
  armeabi-v7a) NAME=simplex-armv7a.apk  APK_SHA256=3a89d2f825ce1a30ff51b30487c1b0b58de6eba03426d1500112b7417e659fdc ;;
  *) echo "unknown ABI $ABI (arm64-v8a or armeabi-v7a)" >&2; exit 1 ;;
esac

here=$(cd "$(dirname "$0")" && pwd)
dl=${SIMPLEX_DL:-$HOME/.l0ck-ecp-toolchain/dl/simplex-$VERSION}
out="$here/../app/src/main/jniLibs/$ABI"
mkdir -p "$dl" "$out"
apk="$dl/$NAME"
if [ ! -f "$apk" ]; then
  curl -sSfL -o "$apk" "https://github.com/simplex-chat/simplex-chat/releases/download/$VERSION/$NAME"
fi
echo "$APK_SHA256  $apk" | sha256sum -c -
unzip -o -j -q "$apk" "lib/$ABI/libsimplex.so" -d "$out"

# libsimplexshim.so (simplex_shim.c): the symbols the core needs that Android does not
# export; the app loads it, and the core with it
ndk=${ANDROID_NDK_HOME:-$HOME/.l0ck-ecp-toolchain/sdk/ndk/28.2.13676358}
case "$ABI" in
  arm64-v8a)   cc=aarch64-linux-android26-clang ;;
  armeabi-v7a) cc=armv7a-linux-androideabi26-clang ;;
esac
"$(ls -d "$ndk"/toolchains/llvm/prebuilt/*/bin | head -1)/$cc" -shared -fPIC -O2 -s \
  -o "$out/libsimplexshim.so" "$here/simplex_shim.c" -L"$out" -lsimplex
ls -la "$out/libsimplex.so" "$out/libsimplexshim.so"
