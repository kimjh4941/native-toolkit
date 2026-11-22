#!/usr/bin/env bash
# Stage 1a entry-layer probe. Simulators only.
#
#   STAGE1A_WORK=<scratch folder> STAGE1A_SIM=<simulator UDID> \
#   STAGE1A_BUILD_XCODE=<Xcode 26.6>/Contents/Developer STAGE1A_CONSUMER_XCODE=<Xcode 26.3>/Contents/Developer ./run.sh <step>...
#
# Steps:
#   ioslib     archive IosLibrary (repo project, unchanged) with the build Xcode -> xcf/ios-native-toolkit.xcframework
#   capi       generate + archive IosLibraryCApi with the build Xcode -> xcf/ios-native-toolkit-capi.xcframework
#   inspect    nm -gU / contents / otool -L / codesign of both xcframeworks
#   test       IosLibraryCApiTests on the simulator: plain, ASan, TSan (build Xcode)
#   consumers  generate + build Smoke and SwiftConsumer with the consumer Xcode, run them on the simulator
#   exception  run Smoke with the UIKit exception scenarios (STAGE1A_IPAD_SIM for kind 2)
#   archive    try a device archive of Smoke (needs a profile), then verify the signatures in the simulator app
#   fallback   generate + build the fallback (C entry + table) with the consumer Xcode, run Smoke against it
#   clean      delete the large build products under STAGE1A_WORK
#
# Toolchains are chosen per command with DEVELOPER_DIR; xcode-select is never changed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../../../../.." && pwd)"
WORK="${STAGE1A_WORK:?set STAGE1A_WORK}"
SIM="${STAGE1A_SIM:-}"
BUILD_XCODE="${STAGE1A_BUILD_XCODE:?set STAGE1A_BUILD_XCODE to the Developer folder of Xcode 26.6}"
CONSUMER_XCODE="${STAGE1A_CONSUMER_XCODE:?set STAGE1A_CONSUMER_XCODE to the Developer folder of Xcode 26.3}"
LOGS="$WORK/logs"
mkdir -p "$LOGS" "$WORK/xcf" "$WORK/arch"

b() { DEVELOPER_DIR="$BUILD_XCODE" "$@"; }
c() { DEVELOPER_DIR="$CONSUMER_XCODE" "$@"; }
need_sim() { [[ -n "$SIM" ]] || { echo "set STAGE1A_SIM" >&2; exit 1; }; }

archive_pair() { # <dev> <project> <scheme> <name> [settings...]
  local dev=$1 project=$2 scheme=$3 name=$4; shift 4
  for p in "iOS:dev" "iOS Simulator:sim"; do
    DEVELOPER_DIR="$dev" xcodebuild archive -project "$project" -scheme "$scheme" -configuration Release \
      -destination "generic/platform=${p%%:*}" -archivePath "$WORK/arch/$name-${p##*:}.xcarchive" \
      -derivedDataPath "$WORK/dd-$name" SKIP_INSTALL=NO CODE_SIGNING_ALLOWED=NO "$@" \
      > "$LOGS/archive-$name-${p##*:}.log" 2>&1 || { tail -30 "$LOGS/archive-$name-${p##*:}.log"; exit 1; }
  done
}

make_xcf() { # <dev> <name> <framework> <output>
  rm -rf "$WORK/xcf/$4"
  DEVELOPER_DIR="$1" xcodebuild -create-xcframework \
    -framework "$WORK/arch/$2-dev.xcarchive/Products/Library/Frameworks/$3.framework" \
    -framework "$WORK/arch/$2-sim.xcarchive/Products/Library/Frameworks/$3.framework" \
    -output "$WORK/xcf/$4" > "$LOGS/xcf-$2.log"
}

launch() { # <dev> <udid> <bundle id> [args...]
  local dev=$1 udid=$2 bid=$3; shift 3
  DEVELOPER_DIR="$dev" xcrun simctl launch --console-pty --terminate-running-process "$udid" "$bid" "$@" 2>&1 \
    | tr -d '\r' | grep -E '^(SMOKE|SWIFTAPP)|Terminating|uncaught|libc\+\+abi|\*\*\*' || true
}

step_ioslib() {
  archive_pair "$BUILD_XCODE" "$REPO/ios/IosLibrary/IosLibrary.xcodeproj" IosLibrary ioslib BUILD_LIBRARY_FOR_DISTRIBUTION=YES
  make_xcf "$BUILD_XCODE" ioslib IosLibrary ios-native-toolkit.xcframework
}

step_capi() {
  ruby "$HERE/gen_projects.rb" "$WORK" capi
  archive_pair "$BUILD_XCODE" "$WORK/capi/IosLibraryCApi.xcodeproj" IosLibraryCApi capi
  make_xcf "$BUILD_XCODE" capi IosLibraryCApi ios-native-toolkit-capi.xcframework
}

step_inspect() {
  for xcf in ios-native-toolkit ios-native-toolkit-capi; do
    echo "== $xcf"
    (cd "$WORK/xcf/$xcf.xcframework" && find . -not -path '*/_CodeSignature*' | sort)
    for slice in "$WORK/xcf/$xcf.xcframework"/ios-*; do
      local bin; bin=$(find "$slice" -maxdepth 2 -type f -perm -u+x -not -name '*.plist' | head -1)
      for arch in $(lipo -archs "$bin"); do
        echo "-- $(basename "$slice") $arch: exported $(nm -gU -arch "$arch" "$bin" | wc -l | tr -d ' '), non-_ntk_ $(nm -gU -arch "$arch" "$bin" | awk '{print $NF}' | grep -vc '^_ntk_' || true)"
      done
      echo "-- codesign: $(codesign -dv "$slice"/*.framework 2>&1 | head -1)"
    done
  done
  local capi="$WORK/xcf/ios-native-toolkit-capi.xcframework/ios-arm64/IosLibraryCApi.framework/IosLibraryCApi"
  echo "== exported symbols (ios-arm64)"; nm -gU "$capi" | awk '{print $NF}'
  echo "== undefined Swift-runtime / compatibility imports"; otool -L "$capi" | sed 1d
  echo "== Info.plist"; plutil -p "$(dirname "$capi")/Info.plist" | grep -E 'DTXcode|MinimumOS|CFBundleIdentifier|DTSDKName'
}

step_test() {
  need_sim
  ruby "$HERE/gen_projects.rb" "$WORK" capi
  for mode in plain asan tsan; do
    local flags=()
    [[ $mode == asan ]] && flags=(-enableAddressSanitizer YES)
    [[ $mode == tsan ]] && flags=(-enableThreadSanitizer YES)
    set +e
    b xcodebuild test -project "$WORK/capi/IosLibraryCApi.xcodeproj" -scheme CApiTests -configuration Debug \
      -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$WORK/dd-test-$mode" \
      -resultBundlePath "$WORK/results-$mode.xcresult" ${flags[@]+"${flags[@]}"} > "$LOGS/test-$mode.log" 2>&1
    local rc=$?
    set -e
    rm -rf "$WORK/results-$mode.xcresult"
    echo "== test $mode rc=$rc"
    grep -E "^Test Case .*(passed|failed)|Executed|^STAGE1A:|^/.*: error:|WARNING: ThreadSanitizer|ERROR: AddressSanitizer|SUMMARY:" "$LOGS/test-$mode.log" | sort -u | head -60
  done
}

step_consumers() {
  need_sim
  ruby "$HERE/gen_projects.rb" "$WORK" consumers
  for app in Smoke SwiftConsumer; do
    c xcodebuild build -project "$WORK/consumers/Consumers.xcodeproj" -scheme "$app" -configuration Release \
      -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$WORK/dd-consumers" > "$LOGS/consumer-$app.log" 2>&1 \
      || { grep -E 'error' "$LOGS/consumer-$app.log" | head -20; exit 1; }
  done
  c xcrun simctl boot "$SIM" 2>/dev/null || true
  c xcrun simctl bootstatus "$SIM" > /dev/null
  local products="$WORK/dd-consumers/Build/Products/Release-iphonesimulator"
  c xcrun simctl install "$SIM" "$products/Smoke.app"
  c xcrun simctl install "$SIM" "$products/SwiftConsumer.app"
  echo "== Smoke (basic)"; launch "$CONSUMER_XCODE" "$SIM" com.jonghyunkim.nativetoolkit.stage1a.smoke
  echo "== SwiftConsumer"; launch "$CONSUMER_XCODE" "$SIM" com.jonghyunkim.nativetoolkit.stage1a.swiftapp
}

step_exception() {
  need_sim
  echo "== Smoke kind=1 (addTextField on an action sheet), $SIM"
  launch "$CONSUMER_XCODE" "$SIM" com.jonghyunkim.nativetoolkit.stage1a.smoke -scenario 1
  if [[ -n "${STAGE1A_IPAD_SIM:-}" ]]; then
    c xcrun simctl boot "$STAGE1A_IPAD_SIM" 2>/dev/null || true
    c xcrun simctl bootstatus "$STAGE1A_IPAD_SIM" > /dev/null
    c xcrun simctl install "$STAGE1A_IPAD_SIM" "$WORK/dd-consumers/Build/Products/Release-iphonesimulator/Smoke.app"
    for kind in 1 2; do
      echo "== Smoke kind=$kind on iPad"
      launch "$CONSUMER_XCODE" "$STAGE1A_IPAD_SIM" com.jonghyunkim.nativetoolkit.stage1a.smoke -scenario "$kind"
    done
  fi
}

step_archive() {
  # A device archive needs a provisioning profile (the user's team), even with CODE_SIGN_IDENTITY=-
  # and CODE_SIGNING_REQUIRED=NO, so this step stops at the attempt and verifies the simulator app
  # that the consumers step built (Embed & Sign with "Sign to Run Locally").
  ruby "$HERE/gen_projects.rb" "$WORK" consumers
  rm -rf "$WORK/arch/Smoke.xcarchive"
  if c xcodebuild archive -project "$WORK/consumers/Consumers.xcodeproj" -scheme Smoke -configuration Release \
      -destination 'generic/platform=iOS' -archivePath "$WORK/arch/Smoke.xcarchive" -derivedDataPath "$WORK/dd-consumers-archive" \
      CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO AD_HOC_CODE_SIGNING_ALLOWED=YES > "$LOGS/archive-smoke.log" 2>&1; then
    echo "== device archive succeeded"
  else
    echo "== device archive refused:"; grep -E 'error:' "$LOGS/archive-smoke.log" | sed 's|^.*error: ||' | head -3
  fi
  local app="$WORK/dd-consumers/Build/Products/Release-iphonesimulator/Smoke.app"
  for f in "$app/Frameworks"/*.framework "$app"; do
    echo "-- $(basename "$f")"
    codesign --verify --deep --strict --verbose=2 "$f" 2>&1 | sed 's|^.*/||'
    codesign -dv "$f" 2>&1 | grep -E 'Signature|TeamIdentifier|flags' || true
  done
  echo "== left in the embedded frameworks"; (cd "$app/Frameworks" && find . -maxdepth 2 | sort)
}

step_fallback() {
  need_sim
  ruby "$HERE/gen_projects.rb" "$WORK" fallback
  archive_pair "$CONSUMER_XCODE" "$WORK/fallback/IosLibraryCApiFallback.xcodeproj" IosLibraryCApi fallback
  make_xcf "$CONSUMER_XCODE" fallback IosLibraryCApi ios-native-toolkit-capi-fallback.xcframework
  local bin="$WORK/xcf/ios-native-toolkit-capi-fallback.xcframework/ios-arm64/IosLibraryCApi.framework/IosLibraryCApi"
  echo "== fallback exports"; nm -gU "$bin" | awk '{print $NF}' | tr '\n' ' '; echo
  echo "== fallback ObjC classes"; otool -ov "$bin" | grep -E '^\s+name 0x' | head -10 || true
  # Run the same smoke against the fallback build (only the capi xcframework differs).
  local keep="$WORK/xcf/ios-native-toolkit-capi.xcframework"
  mv "$keep" "$keep.at-c"
  cp -R "$WORK/xcf/ios-native-toolkit-capi-fallback.xcframework" "$keep"
  ruby "$HERE/gen_projects.rb" "$WORK" consumers
  c xcodebuild build -project "$WORK/consumers/Consumers.xcodeproj" -scheme Smoke -configuration Release \
    -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$WORK/dd-consumers-fallback" > "$LOGS/consumer-fallback.log" 2>&1 \
    || { grep -E 'error' "$LOGS/consumer-fallback.log" | head; rm -rf "$keep"; mv "$keep.at-c" "$keep"; exit 1; }
  rm -rf "$keep"; mv "$keep.at-c" "$keep"
  c xcrun simctl install "$SIM" "$WORK/dd-consumers-fallback/Build/Products/Release-iphonesimulator/Smoke.app"
  echo "== Smoke (basic) against the fallback"; launch "$CONSUMER_XCODE" "$SIM" com.jonghyunkim.nativetoolkit.stage1a.smoke
}

step_clean() {
  rm -rf "$WORK"/dd-* "$WORK"/arch "$WORK"/*.xcresult "$WORK"/capi "$WORK"/consumers "$WORK"/fallback
}

for s in "$@"; do "step_$s"; done
