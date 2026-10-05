#!/usr/bin/env bash
# Runs the Android unit tests, instrumented tests and the sample's UI tests on one device.
#
# Follows section 8 of artifact/topics/android-c-abi/designs/2026-10-03-android-c-abi-ui-test-design.md.
#
# Usage: scripts/test_android.sh --serial <adb serial> [--skip-unit] [--filter <Category>|HostState|Library|Probe]
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

# The library's instrumented tests (android_library/src/androidTest).
LIB_PKG="com.jonghyunkim.nativetoolkit.test"
LIB_RUNNER="${LIB_PKG}/androidx.test.runner.AndroidJUnitRunner"
# Classes that need POST_NOTIFICATIONS revoked first (IT-07, IT-23).
LIB_PERMISSION_CLASSES=(
  com.jonghyunkim.nativetoolkit.notification.NotificationPermissionRequestTest
  com.jonghyunkim.nativetoolkit.notification.ExistingPermissionHelperTest
)
# The release probe (Kotlin API design 0.8: IT-19, IT-22, IT-26).
PROBE_PKG="com.jonghyunkim.android.nativetoolkit.releaseprobe"

# Ordinary UI test classes, run one `am instrument` per class (section 8, step 4).
UI_CLASSES=(
  TagInventoryTest ReceivedShareTagInventoryTest
  NavigationUiTest DialogUiTest
  NotificationSettingsUiTest NotificationStyleUiTest NotificationInteractionUiTest
  NotificationProgressUiTest NotificationCallUiTest NotificationScheduleUiTest NotificationTapUiTest
  NotificationEventDeliveryUiTest ScreenResultSinkInstrumentedTest
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
  n10_permissionRevoked_requestCoroutineAndAllow:permissionRevoked
  n11_permissionRevoked_requestCoroutineAndDeny:permissionRevoked
  n12_permissionRevoked_requestSurvivesTheRecreation:permissionRevoked
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

run_target() {  # <runner> <fully qualified target> [notAnnotation | notclass:<class>...]; prefix the target with "package:" for a package
  local runner="$1" target="$2"; shift 2
  local args=()
  if [[ "${target}" == package:* ]]; then target="${target#package:}"; args+=(--package); fi
  for exclusion in "$@"; do
    if [[ "${exclusion}" == notclass:* ]]; then args+=(--not-class "${exclusion#notclass:}")
    else args+=(--not-annotation "${exclusion}"); fi
  done
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
  # The permission request tests need the permission revoked first (step 5b).
  run_target "${LIB_RUNNER}" "package:com.jonghyunkim.nativetoolkit" "${LIB_PERMISSION_CLASSES[@]/#/notclass:}"
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

# --- 5b. The library's permission request tests (Kotlin API design IT-07, IT-23) ------------
# Revoking the permission kills the test process, so it is revoked before each class starts.
# Each class denies the first request and allows a later one, so it ends with the permission granted.
if [[ -z "${FILTER}" || "${FILTER}" == "Library" ]]; then
  for class in "${LIB_PERMISSION_CLASSES[@]}"; do
    echo "[library] ${class} (permission revoked)"
    adb_s shell pm revoke "${LIB_PKG}" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
    adb_s shell pm clear-permission-flags "${LIB_PKG}" android.permission.POST_NOTIFICATIONS user-set user-fixed >/dev/null 2>&1 || true
    run_target "${LIB_RUNNER}" "${class}"
  done
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

# --- 6b. Release probe (Kotlin API design 0.8 and 12: IT-01, IT-03, IT-07, IT-10, IT-11, IT-19, IT-22, IT-23, IT-26)
# A test-only app built with R8 checks itself and logs "RESULT <case> PASS|FAIL <detail>".
probe_result() {  # <name> <passed|failed> [message]
  python3 -c 'import json,sys; print(json.dumps({"test": "Probe#" + sys.argv[1], "result": sys.argv[2], "message": sys.argv[3]}))' \
    "$1" "$2" "${3:-}" >> "${RESULTS}"
  echo "  ${2}${3:+: $3}"
}

probe_case() {  # <package> <case> <timeout s>; prints "PASS ..." or "FAIL ...", or nothing on timeout
  local package="$1" case="$2" end=$(( $(date +%s) + $3 )) line=""
  adb_s logcat -c
  adb_s shell am start -W -n "${package}/${PROBE_PKG}.ProbeActivity" --es case "${case}" >/dev/null
  while (( $(date +%s) < end )); do
    line="$(adb_s logcat -d -s NtkProbe:I | grep -m1 "RESULT ${case} " || true)"
    [[ -n "${line}" ]] && break
    sleep 2
  done
  if [[ -n "${line}" ]]; then echo "${line#*RESULT ${case} }"; fi
}

probe_record() {  # <name> <outcome from probe_case>
  if [[ "$2" == PASS* ]]; then probe_result "$1" passed "${2#PASS }"
  else probe_result "$1" failed "${2:-no result within the time limit}"; fi
}

probe_wait() {  # <case> <timeout s>; like probe_case for a result the probe logs without being started
  local case="$1" end=$(( $(date +%s) + $2 )) line=""
  while (( $(date +%s) < end )); do
    line="$(adb_s logcat -d -s NtkProbe:I | grep -m1 "RESULT ${case} " || true)"
    [[ -n "${line}" ]] && break
    sleep 2
  done
  if [[ -n "${line}" ]]; then echo "${line#*RESULT ${case} }"; fi
}

# The centre of the first view whose text is [text], from a UI dump; nothing when there is none.
ui_point() {  # <text>
  adb_s shell uiautomator dump /sdcard/ntk-probe-dump.xml >/dev/null 2>&1 || true
  adb_s shell cat /sdcard/ntk-probe-dump.xml 2>/dev/null | python3 -c '
import re, sys
m = re.search(r"text=\"" + re.escape(sys.argv[1]) + r"\"[^>]*?bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"", sys.stdin.read())
print("" if not m else f"{(int(m[1]) + int(m[3])) // 2} {(int(m[2]) + int(m[4])) // 2}")' "$1"
}

ui_has_id() {  # <resource id>; whether a view with that id is on screen
  adb_s shell uiautomator dump /sdcard/ntk-probe-dump.xml >/dev/null 2>&1 || true
  adb_s shell cat /sdcard/ntk-probe-dump.xml 2>/dev/null | grep -q "resource-id=\"$1\""
}

# Kills the probe's process from the background, as the system does when it needs memory.
probe_kill() {
  adb_s shell input keyevent KEYCODE_HOME
  sleep 2
  adb_s shell am kill "${PROBE_PKG}"
  sleep 1
  [[ -z "$(adb_s shell pidof "${PROBE_PKG}" | tr -d '\r')" ]]
}

# Taps the probe's notification titled [title] in the shade.
tap_notification() {  # <title>
  local point=""
  adb_s shell cmd statusbar expand-notifications
  for _ in 1 2 3 4 5; do
    sleep 1
    point="$(ui_point "$1")"
    [[ -n "${point}" ]] && break
  done
  [[ -n "${point}" ]] || { adb_s shell cmd statusbar collapse; return 1; }
  adb_s shell input tap ${point}
  sleep 2
  adb_s shell cmd statusbar collapse
}

# Brings the task of the probe's FragmentActivity back, as Recents does: the system recreates the
# Activity with its saved state, without a new instance.
probe_resume_task() {
  adb_s logcat -c
  # am start warns, with a non-zero status, that it brought the task to the front instead.
  adb_s shell am start -f 0x10000000 -n "${PROBE_PKG}/${PROBE_PKG}.ProbeFragmentActivity" >/dev/null 2>&1 || true
}

if [[ -z "${FILTER}" || "${FILTER}" == "Probe" ]]; then
  echo "[probe] building the release probe (R8)"
  (cd "${ANDROID_DIR}" && ./gradlew --no-daemon -q :releaseProbe:assembleFullRelease :releaseProbe:assembleFullNextRelease \
    :releaseProbe:assembleNoPermissionsRelease :releaseProbe:assembleNoStartupRelease)
  PROBE_APK="${ANDROID_DIR}/AndroidLibraryExample/releaseProbe/build/outputs/apk"
  for package in "${PROBE_PKG}" "${PROBE_PKG}.nopermissions"; do adb_s uninstall "${package}" >/dev/null 2>&1 || true; done

  echo "[probe] IT-22 startup, host, launch activity, receiver and schedule under R8"
  adb_s install "${PROBE_APK}/full/release/releaseProbe-full-release.apk" >/dev/null
  adb_s shell pm grant "${PROBE_PKG}" android.permission.POST_NOTIFICATIONS
  adb_s shell appops set "${PROBE_PKG}" SCHEDULE_EXACT_ALARM allow
  probe_record IT-22_r8 "$(probe_case "${PROBE_PKG}" r8 150)"

  echo "[probe] IT-26 a schedule of the earlier version fires after install -r of the later one"
  outcome="$(probe_case "${PROBE_PKG}" scheduleForUpdate 30)"
  if [[ "${outcome}" == PASS* ]]; then
    trigger="${outcome##*triggerAt=}"
    adb_s install -r "${PROBE_APK}/fullNext/release/releaseProbe-fullNext-release.apk" >/dev/null
    wait_until_epoch_ms $(( trigger + 15000 ))
    probe_record IT-26_update "$(probe_case "${PROBE_PKG}" verifyAfterUpdate 40)"
    echo "[probe] IT-01, IT-23 Startup disabled: isScheduled from the store, manual initialization"
    adb_s install -r "${PROBE_APK}/noStartup/release/releaseProbe-noStartup-release.apk" >/dev/null
    probe_record IT-01_withoutStartup "$(probe_case "${PROBE_PKG}" withoutStartup 30)"
  else
    probe_record IT-26_update "scheduleForUpdate: ${outcome}"
    probe_result IT-01_withoutStartup failed "not run: scheduleForUpdate failed"
  fi
  adb_s uninstall "${PROBE_PKG}" >/dev/null 2>&1 || true

  echo "[probe] IT-10, IT-11 notification taps after the process was killed"
  adb_s install "${PROBE_APK}/full/release/releaseProbe-full-release.apk" >/dev/null
  adb_s shell pm grant "${PROBE_PKG}" android.permission.POST_NOTIFICATIONS
  # One notification at a time: the system groups two, and a tap on the group only opens the app.
  outcome="$(probe_case "${PROBE_PKG}" postColdTap 20)"
  if [[ "${outcome}" != PASS* ]]; then
    probe_record IT-10_coldStart "postColdTap: ${outcome}"
  elif probe_kill && tap_notification "Probe cold tap"; then
    sleep 3
    probe_record IT-10_coldStart "$(probe_case "${PROBE_PKG}" coldEvents 20)"
  else
    probe_result IT-10_coldStart failed "the process stayed or the notification was not found"
  fi
  outcome="$(probe_case "${PROBE_PKG}" postColdLaunch 20)"
  if [[ "${outcome}" != PASS* ]]; then
    probe_record IT-11_coldLaunch "postColdLaunch: ${outcome}"
  elif probe_kill; then
    adb_s logcat -c
    if tap_notification "Probe cold launch"; then
      probe_record IT-11_coldLaunch "$(probe_wait coldLaunch 20)"
    else
      probe_result IT-11_coldLaunch failed "the notification was not found"
    fi
  else
    probe_result IT-11_coldLaunch failed "the process stayed"
  fi

  echo "[probe] IT-03 a dialog restored after a process death closes"
  outcome="$(probe_case "${PROBE_PKG}" dialogBeforeKill 20)"
  if [[ "${outcome}" == PASS* ]] && probe_kill; then
    probe_resume_task
    outcome="$(probe_wait afterKill 20)"
    [[ "${outcome}" == PASS* && -n "$(ui_point "Probe kill dialog")" ]] && outcome="FAIL the dialog is on screen"
    probe_record IT-03_afterProcessDeath "${outcome}"
  else
    probe_record IT-03_afterProcessDeath "dialogBeforeKill: ${outcome:-the process stayed}"
  fi

  echo "[probe] IT-07 a permission request restored after a process death does not launch again"
  adb_s shell pm revoke "${PROBE_PKG}" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  adb_s shell pm clear-permission-flags "${PROBE_PKG}" android.permission.POST_NOTIFICATIONS user-set user-fixed >/dev/null 2>&1 || true
  outcome="$(probe_case "${PROBE_PKG}" permissionBeforeKill 20)"
  if [[ "${outcome}" == PASS* ]] && ui_has_id "com.android.permissioncontroller:id/permission_deny_button" && probe_kill; then
    probe_resume_task
    sleep 3
    # The system dialog of the dead request may come back with the task; close it once.
    if ui_has_id "com.android.permissioncontroller:id/permission_deny_button"; then
      adb_s shell input keyevent KEYCODE_BACK
    fi
    outcome="$(probe_wait afterKill 20)"
    sleep 3
    if [[ "${outcome}" == PASS* ]] && ui_has_id "com.android.permissioncontroller:id/permission_deny_button"; then
      outcome="FAIL the restored request showed the permission dialog again"
    fi
    probe_record IT-07_afterProcessDeath "${outcome}"
  else
    probe_record IT-07_afterProcessDeath "permissionBeforeKill: ${outcome:-the dialog did not show or the process stayed}"
  fi
  adb_s uninstall "${PROBE_PKG}" >/dev/null 2>&1 || true

  echo "[probe] IT-19 the library without its permissions"
  adb_s install "${PROBE_APK}/noPermissions/release/releaseProbe-noPermissions-release.apk" >/dev/null
  probe_record IT-19_permissions "$(probe_case "${PROBE_PKG}.nopermissions" permissions 40)"
  adb_s uninstall "${PROBE_PKG}.nopermissions" >/dev/null 2>&1 || true

  echo "[probe] IT-19 merged manifests: a removed foreground service permission takes its service along"
  AAPT2="$(ls -d "${ANDROID_HOME:-${HOME}/Library/Android/sdk}"/build-tools/*/aapt2 | sort -V | tail -1)"
  manifest_problems="$(python3 - "${AAPT2}" "${PROBE_APK}/full/release/releaseProbe-full-release.apk" \
    "${PROBE_APK}/noPermissions/release/releaseProbe-noPermissions-release.apk" <<'PY'
import re, subprocess, sys
aapt2, full, removed = sys.argv[1:4]
PERMISSIONS = ["POST_NOTIFICATIONS", "RECEIVE_BOOT_COMPLETED", "SCHEDULE_EXACT_ALARM", "USE_FULL_SCREEN_INTENT",
               "FOREGROUND_SERVICE", "FOREGROUND_SERVICE_DATA_SYNC", "FOREGROUND_SERVICE_SPECIAL_USE"]
PROGRESS = "com.jonghyunkim.nativetoolkit.notification.presentation.progress.ProgressForegroundService"
CALL = "com.jonghyunkim.nativetoolkit.notification.presentation.call.CallStyleForegroundService"
# The service each foreground service permission is for (Kotlin API design 8.12).
NEEDS = {"FOREGROUND_SERVICE": [PROGRESS, CALL], "FOREGROUND_SERVICE_DATA_SYNC": [PROGRESS],
         "FOREGROUND_SERVICE_SPECIAL_USE": [CALL]}
def read(apk):
    tree = subprocess.run([aapt2, "dump", "xmltree", "--file", "AndroidManifest.xml", apk],
                          capture_output=True, text=True, check=True).stdout
    perms = set(re.findall(r'android\.permission\.([A-Z_]+)" \(Raw', tree))
    services = set()
    lines = tree.splitlines()
    for i, line in enumerate(lines):
        if line.strip().startswith("E: service"):
            for follow in lines[i + 1:i + 8]:
                m = re.search(r':name\(0x[0-9a-f]+\)="([^"]+)"', follow)
                if m:
                    services.add(m.group(1)); break
    return perms, services
problems = []
perms, services = read(full)
for p in PERMISSIONS:
    if p not in perms: problems.append(f"full: {p} missing")
for s in (PROGRESS, CALL):
    if s not in services: problems.append(f"full: {s} missing")
perms, services = read(removed)
for p in PERMISSIONS:
    if p in perms: problems.append(f"noPermissions: {p} still declared")
for p, needed in NEEDS.items():
    if p not in perms:
        for s in needed:
            if s in services: problems.append(f"noPermissions: {s} kept without {p}")
print("; ".join(problems))
PY
)"
  if [[ -z "${manifest_problems}" ]]; then probe_result IT-19_manifest passed "merged manifests as design 8.12"
  else probe_result IT-19_manifest failed "${manifest_problems}"; fi
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
