#!/usr/bin/env bash
# Runs the Android unit tests, instrumented tests and the sample's UI tests on one device.
#
# Follows section 8 of artifact/topics/android-c-abi/designs/2026-10-03-android-c-abi-ui-test-design.md.
#
# Usage: scripts/test_android.sh --serial <adb serial> [--skip-unit] [--filter <Category>]
#          [--include-host] [--baseline]
#   --include-host  also run H-01 to H-04 (updates the sample and reboots the device twice)
#   --baseline      save the results as the baseline; needs a full run (--include-host, no
#                   --filter, no --skip-unit) without failures
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
INCLUDE_HOST=0
SAVE_BASELINE=0

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial) SERIAL="$2"; shift 2 ;;
    --skip-unit) SKIP_UNIT=1; shift ;;
    --filter) FILTER="$2"; shift 2 ;;
    --include-host) INCLUDE_HOST=1; shift ;;
    --baseline) SAVE_BASELINE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done
[[ -n "${SERIAL}" ]] || { echo "Error: --serial is required (a device and an emulator may both be connected)" >&2; exit 2; }
if [[ "${SAVE_BASELINE}" -eq 1 && ( -n "${FILTER}" || "${SKIP_UNIT}" -eq 1 || "${INCLUDE_HOST}" -eq 0 ) ]]; then
  echo "Error: --baseline needs a full run: add --include-host and drop --filter and --skip-unit" >&2; exit 2
fi

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
MODEL="$(adb_s shell getprop ro.product.model | tr -d '\r' | tr ' ' '_')"
API="$(adb_s shell getprop ro.build.version.sdk | tr -d '\r')"
BASELINE="${ROOT_DIR}/scripts/test_android.baseline.${MODEL}-${API}.json"
if [[ -f "${BASELINE}" ]] && ! grep -qF "\"fingerprint\": \"${FINGERPRINT}\"" "${BASELINE}"; then
  echo "Warning: the fingerprint differs from the baseline's; take the baseline again (README 7.2)" >&2
fi
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
  (cd "${ANDROID_DIR}" && ./gradlew --no-daemon -q :android_library:testDebugUnitTest :unity_android_plugin:testDebugUnitTest :app:testDebugUnitTest)
  python3 - "${ANDROID_DIR}" >> "${RESULTS}" <<'PY'
import glob, json, sys, xml.etree.ElementTree as ET
root = sys.argv[1]
for pattern in ["android_library/build/test-results/testDebugUnitTest/*.xml",
                "unity_android_plugin/build/test-results/testDebugUnitTest/*.xml",
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
  run_target "com.jonghyunkim.nativetoolkit.test/androidx.test.runner.AndroidJUnitRunner" "package:com.jonghyunkim.nativetoolkit"
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

# --- 6. Host cases (section 3.7) -----------------------------------------------------------
host_result() {  # <name> <passed|failed> [message]
  python3 -c 'import json,sys; print(json.dumps({"test": "Host#" + sys.argv[1], "result": sys.argv[2], "message": sys.argv[3]}))' \
    "$1" "$2" "${3:-}" >> "${RESULTS}"
  echo "  ${2}${3:+: $3}"
}

# The sample's notification IDs, read from `dumpsys notification` as it streams; nothing is saved.
sample_notification_ids() {
  adb_s shell dumpsys notification --noredact | python3 -c '
import re, sys
pattern = re.compile(r"NotificationRecord\(0x[0-9a-f]+: pkg=" + re.escape(sys.argv[1]) + r" user=\S+ id=(-?\d+) ")
print(" ".join(sorted({m.group(1) for line in sys.stdin for m in [pattern.search(line)] if m})))' "${PKG}"
}

has_id() { [[ " $1 " == *" $2 "* ]]; }

# Waits up to 240 s for notification [id] and prints the sample's IDs at the end. After a reboot,
# BOOT_COMPLETED reaches the sample late (about 85 s after boot on the emulator).
wait_for_id() {
  local id="$1" ids="" end=$(( $(date +%s) + 240 ))
  while :; do
    ids="$(sample_notification_ids)"
    has_id "${ids}" "${id}" && break
    (( $(date +%s) < end )) || break
    sleep 5
  done
  echo "${ids}"
}

# Closes a system "not responding" dialog (seen on the emulator right after a reboot).
close_anr_dialogs() {
  for _ in 1 2 3 4 5; do
    adb_s shell dumpsys window | grep -q 'mCurrentFocus=.*Not Responding' || return 0
    adb_s shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null
    adb_s shell input keyevent KEYCODE_BACK
    sleep 2
  done
}

# Runs a HostPhaseTest method and prints the trigger time (epoch ms) it scheduled for.
host_phase() {
  local method="$1" raw="${OUT_DIR}/Host_${1}.txt"
  adb_s logcat -c
  python3 "${ROOT_DIR}/scripts/android_instrument.py" --adb "${ADB}" --serial "${SERIAL}" --runner "${RUNNER}" \
    --target "${PKG}.HostPhaseTest#${method}" --raw "${raw}" > "${OUT_DIR}/Host_${method}.jsonl"
  grep -q '"result": "passed"' "${OUT_DIR}/Host_${method}.jsonl" || return 1
  adb_s logcat -d -s HostPhaseTest:I | sed -n 's/.*HOST_TRIGGER_AT=\([0-9]*\).*/\1/p' | head -1
}

wait_until_epoch_ms() {  # <epoch ms>; uses the device clock
  local target_s=$(( $1 / 1000 ))
  while (( $(adb_s shell date +%s | tr -d '\r') < target_s )); do sleep 2; done
}

reboot_and_wait() {
  adb_s reboot
  adb_s wait-for-device
  local end=$(( $(date +%s) + 180 ))
  until [[ "$(adb_s shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
    (( $(date +%s) < end )) || return 1
    sleep 3
  done
  adb_s shell input keyevent KEYCODE_WAKEUP
  adb_s shell wm dismiss-keyguard
  adb_s shell svc power stayon true
}

# Clears the schedules and notifications a host case left: `pm clear` force-stops the sample,
# which cancels its alarms and notifications.
host_cleanup() {
  adb_s shell pm clear "${PKG}" >/dev/null
  restore_device
}

if [[ "${INCLUDE_HOST}" -eq 1 && -z "${FILTER}" ]]; then
  if adb_s shell dumpsys window | grep -qE '^ +secure=true'; then
    echo "Error: the device has a secure lock; after a reboot BOOT_COMPLETED waits for the unlock (3.5)" >&2
    exit 1
  fi
  HOST_MARGIN_MS=15000
  SAMPLE_APK="${APK_DIR}/debug/app-debug.apk"

  echo "[host] H-01 install -r keeps both schedules"
  host_cleanup
  if trigger="$(host_phase h01_scheduleBeforeInstallReplace)" && [[ -n "${trigger}" ]]; then
    adb_s install -r -t "${SAMPLE_APK}" >/dev/null
    wait_until_epoch_ms $(( trigger + HOST_MARGIN_MS ))
    ids="$(wait_for_id 9102)"
    if has_id "${ids}" 9101 && has_id "${ids}" 9102; then host_result H-01_installReplace passed
    else host_result H-01_installReplace failed "expected 9101 and 9102; shown: [${ids}]"; fi
  else
    host_result H-01_installReplace failed "the first phase failed (see Host_h01_*.txt)"
  fi

  echo "[host] H-02 reboot keeps only the persisted schedule"
  host_cleanup
  host_alive=1
  if trigger="$(host_phase h02_scheduleBeforeReboot)" && [[ -n "${trigger}" ]]; then
    if reboot_and_wait; then
      wait_until_epoch_ms $(( trigger + HOST_MARGIN_MS ))
      ids="$(wait_for_id 9101)"
      if has_id "${ids}" 9101 && ! has_id "${ids}" 9102; then host_result H-02_reboot passed
      else host_result H-02_reboot failed "expected 9101 without 9102; shown: [${ids}]"; fi
    else
      host_alive=0; host_result H-02_reboot failed "the device did not finish booting within 180 s"
    fi
  else
    host_result H-02_reboot failed "the first phase failed (see Host_h02_*.txt)"
  fi

  echo "[host] H-03 a schedule that comes due during the reboot is shown after it"
  if [[ "${host_alive}" -eq 1 ]]; then
    host_cleanup
    if trigger="$(host_phase h03_scheduleThatComesDueDuringReboot)" && [[ -n "${trigger}" ]]; then
      if reboot_and_wait; then
        ids="$(wait_for_id 9103)"
        if has_id "${ids}" 9103; then host_result H-03_dueDuringReboot passed
        else host_result H-03_dueDuringReboot failed "expected 9103; shown: [${ids}]"; fi
      else
        host_alive=0; host_result H-03_dueDuringReboot failed "the device did not finish booting within 180 s"
      fi
    else
      host_result H-03_dueDuringReboot failed "the first phase failed (see Host_h03_*.txt)"
    fi
  else
    host_result H-03_dueDuringReboot failed "skipped: the device did not come back from H-02"
  fi

  echo "[host] H-04 a share received while the sample is not running"
  if [[ "${host_alive}" -eq 1 ]]; then
    host_cleanup
    close_anr_dialogs
    adb_s shell am force-stop "${PKG}"
    adb_s shell am start -W -a android.intent.action.SEND -t text/plain \
      --es android.intent.extra.TEXT HostShareH04 -n "${PKG}/.MainActivity" >/dev/null
    values=""
    for _ in $(seq 1 10); do
      # Only the three values are taken from the dump; the dump itself is removed from the device.
      values="$(adb_s exec-out "uiautomator dump /sdcard/ntk_h04.xml >/dev/null && cat /sdcard/ntk_h04.xml; rm -f /sdcard/ntk_h04.xml" | python3 -c '
import re, sys
xml = sys.stdin.read()
def value(tag):
    m = re.search(r"<node [^>]*text=\"([^\"]*)\"[^>]*resource-id=\"" + re.escape(tag) + r"\"", xml)
    return m.group(1) if m else ""
print("|".join(value("receivedShare." + name) for name in ("action", "mimeType", "text")))')"
      [[ "${values}" == "android.intent.action.SEND|text/plain|HostShareH04" ]] && break
      sleep 2
    done
    if [[ "${values}" == "android.intent.action.SEND|text/plain|HostShareH04" ]]; then host_result H-04_coldShare passed
    else host_result H-04_coldShare failed "action|type|text was [${values}]"; fi
    adb_s shell am force-stop "${PKG}"
  else
    host_result H-04_coldShare failed "skipped: the device did not come back from H-02 or H-03"
  fi
  host_cleanup
fi

# --- 7. Device state -----------------------------------------------------------------------
restore_device
STATE_OK=1
adb_s shell dumpsys package "${PKG}" | grep -q 'POST_NOTIFICATIONS: granted=true' || STATE_OK=0
adb_s shell appops get "${PKG}" SCHEDULE_EXACT_ALARM | grep -q 'allow' || STATE_OK=0
[[ "${STATE_OK}" -eq 1 ]] || echo "Error: the device state was not restored (notification permission, exact alarms)" >&2

# --- 8. Summary and baseline ---------------------------------------------------------------
set +e
python3 - "${RESULTS}" "${BASELINE}" "${SAVE_BASELINE}" "${FINGERPRINT}" "${MODEL}" "${API}" <<'PY'
import json, os, sys
results_path, baseline_path, save, fingerprint, model, api = sys.argv[1:7]
results = [json.loads(line) for line in open(results_path, encoding="utf-8") if line.strip()]
counts = {}
for r in results:
    counts[r["result"]] = counts.get(r["result"], 0) + 1
print(f"[summary] {len(results)} results: " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
for r in results:
    if r["result"] == "failed":
        print(f"  FAILED {r['test']}: {r['message']}")
current = {r["test"]: r["result"] for r in results}
if os.path.exists(baseline_path):
    base = json.load(open(baseline_path, encoding="utf-8"))["results"]
    changed = sorted(t for t in current.keys() & base.keys() if current[t] != base[t])
    added = sorted(current.keys() - base.keys())
    removed = sorted(base.keys() - current.keys())
    print(f"[baseline] {os.path.basename(baseline_path)}: changed={len(changed)}, added={len(added)}, removed={len(removed)}")
    for t in changed:
        print(f"  CHANGED {t}: {base[t]} -> {current[t]}")
    for t in added:
        print(f"  ADDED {t}: {current[t]}")
    for t in removed:
        print(f"  REMOVED {t}: {base[t]}")
else:
    print(f"[baseline] none for {model}-{api}")
failed = bool(counts.get("failed"))
if save == "1":
    if failed:
        print("[baseline] not saved: the run has failures")
    else:
        with open(baseline_path, "w", encoding="utf-8") as f:
            json.dump({"model": model, "api": int(api), "fingerprint": fingerprint,
                       "results": dict(sorted(current.items()))}, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"[baseline] saved {os.path.basename(baseline_path)}")
sys.exit(1 if failed else 0)
PY
SUMMARY_EXIT=$?
set -e
[[ "${SUMMARY_EXIT}" -eq 0 && "${STATE_OK}" -eq 1 ]] || exit 1
