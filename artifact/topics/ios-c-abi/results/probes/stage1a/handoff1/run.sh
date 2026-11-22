#!/usr/bin/env bash
# Stage 1a hand-off 1: checks on simulators only (run build.sh first).
#
#   STAGE1A_BUILD_XCODE=<Xcode 26.6>/Contents/Developer STAGE1A_CONSUMER_XCODE=<Xcode 26.3>/Contents/Developer \
#   STAGE1A_SIM=<simulator UDID> ./run.sh <step>...
#
# Steps:
#   test <mode>  unit + UI tests on STAGE1A_SIM with the build Xcode; mode = plain | asan | tsan
#   inspect      contents, exports and signatures of the built xcframeworks
#   smoke        build the C smoke with both Xcodes against the built xcframeworks, run the 26.3 one
#   clean        delete the work folder (the xcframeworks stay)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../../../../.." && pwd)"
OUT="$REPO/ios/Build/stage1a-handoff1"
WORK="$REPO/ios/Build/stage1a-handoff1-work"
BUILD_XCODE="${STAGE1A_BUILD_XCODE:?set STAGE1A_BUILD_XCODE to the Developer folder of Xcode 26.6}"
CONSUMER_XCODE="${STAGE1A_CONSUMER_XCODE:?set STAGE1A_CONSUMER_XCODE to the Developer folder of Xcode 26.3}"
SIM="${STAGE1A_SIM:?set STAGE1A_SIM}"
mkdir -p "$WORK/logs"

step_test() {
  local mode=$1 flags=()
  [[ $mode == asan ]] && flags=(-enableAddressSanitizer YES)
  [[ $mode == tsan ]] && flags=(-enableThreadSanitizer YES)
  DEVELOPER_DIR="$BUILD_XCODE" ruby "$HERE/gen_projects.rb" "$WORK" "$OUT/ios-native-toolkit-handoff1.xcframework" capi > /dev/null
  set +e
  DEVELOPER_DIR="$BUILD_XCODE" xcodebuild test -project "$WORK/capi/IosLibraryCApi.xcodeproj" -scheme CApiTests -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$WORK/dd-test-$mode" \
    -resultBundlePath "$WORK/results-$mode-$SIM.xcresult" ${flags[@]+"${flags[@]}"} > "$WORK/logs/test-$mode-$SIM.log" 2>&1
  local rc=$?
  set -e
  rm -rf "$WORK/results-$mode-$SIM.xcresult"
  echo "== test $mode rc=$rc"
  grep -E "^Test Case .*(passed|failed)|Executed|^HANDOFF1|^/.*: error:|WARNING: ThreadSanitizer|ERROR: AddressSanitizer|SUMMARY:" \
    "$WORK/logs/test-$mode-$SIM.log" | sed -E "s/^Test Case '-\[[A-Za-z0-9_]+\.//" | sort -u
}

step_inspect() {
  for x in ios-native-toolkit-handoff1 ios-native-toolkit-capi-handoff1; do
    echo "== $x"; (cd "$OUT/$x.xcframework" && find . -not -path '*/_CodeSignature*' | sort | grep -v 'swiftmodule/.*\.' )
    for slice in "$OUT/$x.xcframework"/ios-*; do echo "-- $(basename "$slice"): $(codesign -dv "$slice"/*.framework 2>&1 | head -1 | sed 's|^.*/||')"; done
  done
  cat "$OUT/BUILD-INFO.txt"
}

step_smoke() {
  for pair in "26.6:$BUILD_XCODE" "26.3:$CONSUMER_XCODE"; do
    local name=${pair%%:*} dev=${pair#*:}
    DEVELOPER_DIR="$dev" ruby "$HERE/gen_projects.rb" "$WORK/smoke-$name" "$OUT" smoke > /dev/null
    DEVELOPER_DIR="$dev" xcodebuild build -project "$WORK/smoke-$name/smoke/Smoke.xcodeproj" -scheme Smoke -configuration Release \
      -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$WORK/dd-smoke-$name" > "$WORK/logs/smoke-$name.log" 2>&1 \
      || { grep -E 'error' "$WORK/logs/smoke-$name.log" | head; exit 1; }
    echo "== smoke built with Xcode $name: $(grep -cE ': warning:' "$WORK/logs/smoke-$name.log" || true) warnings"
  done
  DEVELOPER_DIR="$CONSUMER_XCODE" xcrun simctl boot "$SIM" 2>/dev/null || true
  DEVELOPER_DIR="$CONSUMER_XCODE" xcrun simctl bootstatus "$SIM" > /dev/null
  DEVELOPER_DIR="$CONSUMER_XCODE" xcrun simctl install "$SIM" "$WORK/dd-smoke-26.3/Build/Products/Release-iphonesimulator/Smoke.app"
  echo "== smoke (Xcode 26.3 build) on the simulator"
  DEVELOPER_DIR="$CONSUMER_XCODE" xcrun simctl launch --console-pty --terminate-running-process "$SIM" \
    com.jonghyunkim.nativetoolkit.stage1a.handoff1.smoke 2>&1 | tr -d '\r' | grep -E '^SMOKE|Terminating' || true
}

step_clean() { rm -rf "$WORK"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    test) step_test "$2"; shift 2 ;;
    *) "step_$1"; shift ;;
  esac
done
