#!/usr/bin/env bash
# Stage 1a hand-off 1: builds the two probe xcframeworks (ios-arm64 + ios-arm64_x86_64-simulator).
#
#   DEVELOPER_DIR=<Xcode 26.6>/Contents/Developer ./build.sh [--asan]
#
# Output (gitignored by ios/.gitignore):
#   ios/Build/stage1a-handoff1/ios-native-toolkit-handoff1.xcframework       IosLibrary (repo project, unchanged)
#   ios/Build/stage1a-handoff1/ios-native-toolkit-capi-handoff1.xcframework  IosLibraryCApi (this probe)
#   ios/Build/stage1a-handoff1/include/NativeToolkitC/*.h                     the public headers
#   ios/Build/stage1a-handoff1/BUILD-INFO.txt                                 toolchain, commit, exported symbols
# With --asan the same files go to ios/Build/stage1a-handoff1/asan/, built with Address Sanitizer
# (the app that embeds them must enable Address Sanitizer in its scheme so that Xcode embeds the runtime).
# Archives are not signed (D-18). Needs Xcode 26.6 (Swift 6.3: @c @implementation) and the xcodeproj gem.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../../../../.." && pwd)"
: "${DEVELOPER_DIR:?set DEVELOPER_DIR to the Developer folder of Xcode 26.6}"
export DEVELOPER_DIR
xcrun swiftc --version 2>&1 | grep -q 'Swift version 6\.3' || { echo "DEVELOPER_DIR must point to Xcode 26.6 (Swift 6.3)" >&2; exit 1; }

ASAN=""
[[ "${1:-}" == "--asan" ]] && ASAN="asan"
OUT="$REPO/ios/Build/stage1a-handoff1${ASAN:+/asan}"
WORK="$REPO/ios/Build/stage1a-handoff1-work${ASAN:+-asan}"
SAN=()
[[ -n "$ASAN" ]] && SAN=(ENABLE_ADDRESS_SANITIZER=YES)
mkdir -p "$OUT" "$WORK/logs"

archive() { # <project> <scheme> <name> [settings...]
  local project=$1 scheme=$2 name=$3; shift 3
  for p in "iOS:dev" "iOS Simulator:sim"; do
    xcodebuild archive -project "$project" -scheme "$scheme" -configuration Release \
      -destination "generic/platform=${p%%:*}" -archivePath "$WORK/$name-${p##*:}.xcarchive" \
      -derivedDataPath "$WORK/dd-$name" SKIP_INSTALL=NO CODE_SIGNING_ALLOWED=NO "$@" \
      > "$WORK/logs/archive-$name-${p##*:}.log" 2>&1 || { tail -30 "$WORK/logs/archive-$name-${p##*:}.log"; exit 1; }
  done
}

xcf() { # <name> <framework> <output>
  rm -rf "$OUT/$3"
  xcodebuild -create-xcframework \
    -framework "$WORK/$1-dev.xcarchive/Products/Library/Frameworks/$2.framework" \
    -framework "$WORK/$1-sim.xcarchive/Products/Library/Frameworks/$2.framework" \
    -output "$OUT/$3" > "$WORK/logs/xcf-$1.log"
}

echo "[1/3] IosLibrary"
archive "$REPO/ios/IosLibrary/IosLibrary.xcodeproj" IosLibrary ioslib BUILD_LIBRARY_FOR_DISTRIBUTION=YES ${SAN[@]+"${SAN[@]}"}
xcf ioslib IosLibrary ios-native-toolkit-handoff1.xcframework

echo "[2/3] IosLibraryCApi"
ruby "$HERE/gen_projects.rb" "$WORK" "$OUT/ios-native-toolkit-handoff1.xcframework" capi $ASAN > /dev/null
archive "$WORK/capi/IosLibraryCApi.xcodeproj" IosLibraryCApi capi
xcf capi IosLibraryCApi ios-native-toolkit-capi-handoff1.xcframework

echo "[3/3] check and record"
rm -rf "$OUT/include" && mkdir -p "$OUT/include/NativeToolkitC"
cp "$OUT/ios-native-toolkit-capi-handoff1.xcframework/ios-arm64/IosLibraryCApi.framework/Headers/NativeToolkitC/"*.h "$OUT/include/NativeToolkitC/"
status=0
{
  echo "built: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "commit: $(git -C "$REPO" rev-parse --short HEAD)$([[ -z "$(git -C "$REPO" status --porcelain -- ios/IosLibrary artifact/topics/ios-c-abi/results/probes/stage1a)" ]] || echo ' (with uncommitted probe or IosLibrary changes)')"
  echo "xcode: $(xcodebuild -version | tr '\n' ' ')"
  echo "swiftc: $(xcrun swiftc --version 2>&1 | head -1)"
  echo "asan: ${ASAN:-no}"
  for slice in "$OUT/ios-native-toolkit-capi-handoff1.xcframework"/ios-*; do
    bin="$slice/IosLibraryCApi.framework/IosLibraryCApi"
    for arch in $(lipo -archs "$bin"); do
      other=$(nm -gU -arch "$arch" "$bin" | awk '{print $NF}' | grep -v '^_ntk_' || true)
      echo "exports $(basename "$slice") $arch: $(nm -gU -arch "$arch" "$bin" | wc -l | tr -d ' ')${other:+ NON-NTK: $other}"
      [[ -z "$other" ]] || status=1
    done
    for bad in Modules/IosLibraryCApi.swiftmodule Headers/IosLibraryCApi-Swift.h; do
      [[ ! -e "$slice/IosLibraryCApi.framework/$bad" ]] || { echo "UNEXPECTED $bad"; status=1; }
    done
  done
  echo "symbols (ios-arm64):"
  nm -gU "$OUT/ios-native-toolkit-capi-handoff1.xcframework/ios-arm64/IosLibraryCApi.framework/IosLibraryCApi" | awk '{print "  " $NF}'
} > "$OUT/BUILD-INFO.txt"
cat "$OUT/BUILD-INFO.txt"
[[ $status -eq 0 ]] || { echo "export check failed" >&2; exit 1; }
echo "done: $OUT"
