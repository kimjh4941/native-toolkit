#!/usr/bin/env bash
# Runs the Android unit tests, instrumented tests and the sample's UI tests on one device.
#
# Follows section 8 of artifact/topics/android-c-abi/designs/2026-10-03-android-c-abi-ui-test-design.md.
# Stage 0c version: the host-driven update/reboot cases (--include-host) and the baseline
# (--baseline) are added in stage 0d.
#
# Usage: scripts/test_android.sh --serial <adb serial> [--skip-unit] [--filter <Category>]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="${ROOT_DIR}/android"
ADB="${ANDROID_HOME:-${HOME}/Library/Android/sdk}/platform-tools/adb"
PKG="com.jonghyunkim.android.nativetoolkit.example"
RUNNER="${PKG}.test/androidx.test.runner.AndroidJUnitRunner"
INFRA="${PKG}.infra"
SERIAL=""
SKIP_UNIT=0
FILTER=""

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial) SERIAL="$2"; shift 2 ;;
    --skip-unit) SKIP_UNIT=1; shift ;;
    --filter) FILTER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done
[[ -n "${SERIAL}" ]] || { echo "Error: --serial is required (a device and an emulator may both be connected)" >&2; exit 2; }

adb_s() { "${ADB}" -s "${SERIAL}" "$@"; }
OUT_DIR="${ANDROID_DIR}/AndroidLibraryExample/app/build/test_android/$(date +%Y%m%d-%H%M%S)-${SERIAL}"
mkdir -p "${OUT_DIR}"
RESULTS="${OUT_DIR}/results.jsonl"
: > "${RESULTS}"

# Ordinary UI test classes, run one `am instrument` per class (section 8, step 4).
UI_CLASSES=(
  TagInventoryTest ReceivedShareTagInventoryTest
  NavigationUiTest DialogUiTest
  NotificationSettingsUiTest NotificationStyleUiTest NotificationInteractionUiTest
  NotificationProgressUiTest NotificationCallUiTest NotificationScheduleUiTest NotificationTapUiTest
  ShareUiTest ReceivedShareUiTest ReceivedShareLaunchUiTest
  ClipboardSampleScreenUiTest ClipboardAdditionalUiTest
  IncomingShareParserInstrumentedTest MainActivityIncomingShareInstrumentedTest
)
# Host-state cases: "<method>:<state>" (section 3.5, U-5).
HOST_STATE_CASES=(
  n02_exactAlarmDenied_checkReportsIt:exactAlarmDenied
  n50_exactAlarmDenied_scheduleFails:exactAlarmDenied
  n03_permissionRevoked_requestAndAllow:permissionRevoked
  n04_permissionRevoked_requestAndDenyThenCheck:permissionRevoked
  n05_permissionRevoked_showFails:permissionRevoked
  n09_permissionRevoked_foregroundServicesAndScheduleFail:permissionRevoked
)

ORIGINAL_STAYON=""
restore_device() {
  adb_s shell pm grant "${PKG}" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  # A UID-level mode overrides the package-level one; keep it at default so the package mode decides.
  adb_s shell appops set --uid "${PKG}" SCHEDULE_EXACT_ALARM default >/dev/null 2>&1 || true
  adb_s shell appops set "${PKG}" SCHEDULE_EXACT_ALARM allow >/dev/null 2>&1 || true
  adb_s shell appops set "${PKG}" USE_FULL_SCREEN_INTENT allow >/dev/null 2>&1 || true
  if [[ -n "${ORIGINAL_STAYON}" ]]; then
    adb_s shell settings put global stay_on_while_plugged_in "${ORIGINAL_STAYON}" >/dev/null 2>&1 || true
  fi
}
trap restore_device EXIT

# --- 0. Device -----------------------------------------------------------------------------
echo "[device] $(adb_s shell getprop ro.product.model | tr -d '\r') / API $(adb_s shell getprop ro.build.version.sdk | tr -d '\r')"
FINGERPRINT="$(adb_s shell getprop ro.build.fingerprint | tr -d '\r')"
echo "[device] ${FINGERPRINT}"
echo "${FINGERPRINT}" > "${OUT_DIR}/fingerprint.txt"
ORIGINAL_STAYON="$(adb_s shell settings get global stay_on_while_plugged_in | tr -d '\r')"
adb_s shell svc power stayon true
adb_s shell input keyevent KEYCODE_WAKEUP
adb_s shell wm dismiss-keyguard
for _ in 1 2 3 4 5; do
  adb_s shell dumpsys window | grep -q 'isKeyguardShowing=false' && break
  sleep 1
done
if ! adb_s shell dumpsys window | grep -q 'isKeyguardShowing=false'; then
  echo "Error: the device is locked. Unlock it (a secure lock cannot be dismissed by the script)." >&2
  exit 1
fi
if [[ "$(adb_s shell settings get global zen_mode | tr -d '\r')" != "0" ]]; then
  echo "Error: Do Not Disturb is on. Turn it off and run again." >&2
  exit 1
fi

# --- 1. Unit tests -------------------------------------------------------------------------
if [[ "${SKIP_UNIT}" -eq 0 && -z "${FILTER}" ]]; then
  echo "[unit] running"
  (cd "${ANDROID_DIR}" && ./gradlew --no-daemon -q :android_library:testReleaseUnitTest :unity_android_plugin:testReleaseUnitTest :app:testDebugUnitTest)
  python3 - "${ANDROID_DIR}" >> "${RESULTS}" <<'PY'
import glob, json, sys, xml.etree.ElementTree as ET
root = sys.argv[1]
for pattern in ["android_library/build/test-results/testReleaseUnitTest/*.xml",
                "unity_android_plugin/build/test-results/testReleaseUnitTest/*.xml",
                "AndroidLibraryExample/app/build/test-results/testDebugUnitTest/*.xml"]:
    for path in glob.glob(f"{root}/{pattern}"):
        for case in ET.parse(path).getroot().iter("testcase"):
            failed = case.find("failure") is not None or case.find("error") is not None
            print(json.dumps({"test": f"unit:{case.get('classname')}#{case.get('name')}",
                              "result": "failed" if failed else ("skipped" if case.find("skipped") is not None else "passed"),
                              "message": ""}))
PY
fi

# --- 2. Build and install ------------------------------------------------------------------
echo "[install] building"
(cd "${ANDROID_DIR}" && ./gradlew --no-daemon -q :app:assembleDebug :app:assembleDebugAndroidTest :testShareTarget:assembleDebug \
  :android_library:assembleDebugAndroidTest :unity_android_plugin:assembleDebugAndroidTest)
APK_DIR="${ANDROID_DIR}/AndroidLibraryExample/app/build/outputs/apk"
for apk in "${APK_DIR}/debug/app-debug.apk" "${APK_DIR}/androidTest/debug/app-debug-androidTest.apk" \
           "${ANDROID_DIR}/AndroidLibraryExample/testShareTarget/build/outputs/apk/debug/testShareTarget-debug.apk" \
           "${ANDROID_DIR}/android_library/build/outputs/apk/androidTest/debug/android_library-debug-androidTest.apk" \
           "${ANDROID_DIR}/unity_android_plugin/build/outputs/apk/androidTest/debug/unity_android_plugin-debug-androidTest.apk"; do
  adb_s install -r -t "${apk}" >/dev/null
done

# --- 3. Device state -----------------------------------------------------------------------
echo "[state] clearing the sample's data and granting permissions"
adb_s shell pm clear "${PKG}" >/dev/null
restore_device
adb_s shell appops get "${PKG}" USE_FULL_SCREEN_INTENT > "${OUT_DIR}/appops-full-screen-intent.txt" || true

run_target() {  # <runner> <fully qualified target> [notAnnotation...]; prefix the target with "package:" for a package
  local runner="$1" target="$2"; shift 2
  local args=()
  if [[ "${target}" == package:* ]]; then target="${target#package:}"; args+=(--package); fi
  for annotation in "$@"; do args+=(--not-annotation "${annotation}"); done
  python3 "${ROOT_DIR}/scripts/android_instrument.py" --adb "${ADB}" --serial "${SERIAL}" --runner "${runner}" \
    --target "${target}" --raw "${OUT_DIR}/$(echo "${target}" | tr '#' '_').txt" ${args[@]+"${args[@]}"} >> "${RESULTS}"
}

# --- 4. Ordinary classes -------------------------------------------------------------------
for class in "${UI_CLASSES[@]}"; do
  if [[ -n "${FILTER}" ]] && ! grep -q "Category${FILTER}" "${ANDROID_DIR}/AndroidLibraryExample/app/src/androidTest/java/com/jonghyunkim/android/nativetoolkit/example/${class}.kt" 2>/dev/null; then
    continue
  fi
  echo "[ui] ${class}"
  run_target "${RUNNER}" "${PKG}.${class}" "${INFRA}.CategoryHostState" "${INFRA}.CategoryHost"
done
if [[ -z "${FILTER}" ]]; then
  echo "[instrumented] the sample's template, android_library, unity_android_plugin"
  run_target "${RUNNER}" "example.android.ExampleInstrumentedTest"
  run_target "android.library.test/androidx.test.runner.AndroidJUnitRunner" "package:android.library"
  run_target "android.plugin.test/androidx.test.runner.AndroidJUnitRunner" "package:android.unity"
  run_target "android.plugin.test/androidx.test.runner.AndroidJUnitRunner" "package:android.plugin"
fi

# --- 5. Host-state cases -------------------------------------------------------------------
if [[ -z "${FILTER}" || "${FILTER}" == "HostState" ]]; then
  for entry in "${HOST_STATE_CASES[@]}"; do
    method="${entry%%:*}"; state="${entry##*:}"
    echo "[host-state] ${method} (${state})"
    restore_device
    case "${state}" in
      exactAlarmDenied)
        adb_s shell appops set --uid "${PKG}" SCHEDULE_EXACT_ALARM default
        adb_s shell appops set "${PKG}" SCHEDULE_EXACT_ALARM default ;;
      permissionRevoked)
        adb_s shell pm revoke "${PKG}" android.permission.POST_NOTIFICATIONS
        adb_s shell pm clear-permission-flags "${PKG}" android.permission.POST_NOTIFICATIONS user-set user-fixed ;;
    esac
    run_target "${RUNNER}" "${PKG}.NotificationHostStateUiTest#${method}"
  done
  restore_device
fi

# --- Summary -------------------------------------------------------------------------------
python3 - "${RESULTS}" <<'PY'
import json, sys
results = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
counts = {}
for r in results:
    counts[r["result"]] = counts.get(r["result"], 0) + 1
print(f"[summary] {len(results)} results: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
for r in results:
    if r["result"] == "failed":
        print(f"  FAILED {r['test']}: {r['message']}")
sys.exit(1 if counts.get("failed") else 0)
PY
