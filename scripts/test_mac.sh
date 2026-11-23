#!/usr/bin/env bash
# Runs the macOS unit tests and the sample's UI tests in the qualified tart VM, or, after the user
# approved the list, on this Mac.
#
# Follows section 6.3 of artifact/topics/macos-c-abi/designs/2026-11-23-macos-c-abi-ui-test-design.md.
# What runs and every check of what ran is decided in scripts/mac_ui_runner.py; this script runs
# xcodebuild, tart, ssh and tar. Bash 3.2 (the one macOS ships, here and in the VM).
#
# Usage: scripts/test_mac.sh --where vm [--vm <name>] [--feature Dialog|Notification|Share|Clipboard]
#          [--skip-unit] [--baseline] [--name-each-test] [--keep-vm-run]
#        scripts/test_mac.sh --where mac [--allow <c,...>] [--allow-lsregister] [--feature ...] [--skip-unit]
#          (--dry-run | --approved <file>) [--baseline] [--vm <name>]
#   --where             vm or mac; required. The VM must pass the qualification (6.3 step 0) every time;
#                       when it does not, the runner stops and never falls back to this Mac
#   --vm                the tart VM (default ntk-macos-15-new); this Mac's runs enumerate there too
#   --feature           only that feature's UI classes and the common ones; no unit tests
#   --skip-unit         no unit tests
#   --allow             mac only: the categories allowed on this Mac (none by default):
#                       notification,settings,badge,clipboard,sharepicker,panels,coldstart
#   --allow-lsregister  mac only: remove the extra registered copies the --dry-run list showed (U-21)
#   --dry-run           mac only: enumerates in the VM, starts nothing on this Mac (no build), prints
#                       the list, what happens, what to prepare and the time, and writes the approval list
#   --approved          mac only: the approval list the user approved; an approval runs once
#   --baseline          saves the results as the baseline of that environment (6.3 "基準の条件")
#   --name-each-test    vm only: one xcodebuild per test (this Mac always does)
#   --qualification     mac26|mac26-reply|vm-ja: only the U-30 probes of that stage (none are written yet)
#   --keep-vm-run       vm only: leave the VM's run folder (sources, DerivedData, result bundles) for a look
set -euo pipefail

# What a test may touch reaches it only through the runner's own xcodebuild (U-9).
unset TEST_RUNNER_NTK_HOST TEST_RUNNER_NTK_ALLOW TEST_RUNNER_NTK_FIXTURE_DIR TEST_RUNNER_NTK_EXPECTED_COPY \
  NTK_HOST NTK_ALLOW NTK_FIXTURE_DIR NTK_EXPECTED_COPY

DESTINATION="platform=macOS,arch=arm64"
SAMPLE_ID="com.jonghyunkim.mac.nativetoolkit.example"
PREVIEW_KEY="EnablePasteboardPrivacyDeveloperPreview"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
UI_XCTEST_BINARY="MacLibraryExampleUITests-Runner.app/Contents/PlugIns/MacLibraryExampleUITests.xctest/Contents/MacOS/MacLibraryExampleUITests"
TIME_FLAGS=(-parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 120
  -maximum-test-execution-time-allowance 240)
RUN_ID_PATTERN='^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{6}$'

# Runs a command in its own process group with a time limit. When the time is up, the whole group is
# killed (TERM, 30 s, KILL), reaped, and the exit status is 142; INT, TERM and HUP do the same. With a
# pid file, the child's PID (the group's leader) is written there first. stdin is /dev/null.
capped_group() {  # <seconds> <pid file or -> <command...>
  local seconds="$1" pidfile="$2"; shift 2
  perl -e 'my $seconds = shift; my $pidfile = shift; die "time limit: $seconds\n" unless $seconds =~ /^[1-9][0-9]*$/;
           my $pid = fork; die "fork: $!\n" unless defined $pid;
           if ($pid == 0) { setpgrp(0, 0); exec @ARGV or exit 127; }
           setpgrp($pid, $pid);
           if ($pidfile ne "-") { open(my $f, ">", $pidfile) or die "pid file: $!\n"; print $f "$pid\n"; close $f; }
           my $stop = sub { kill "TERM", -$pid; for (1..60) { last if waitpid($pid, 1) > 0; select(undef, undef, undef, 0.5); }
                            kill "KILL", -$pid; waitpid($pid, 0); };
           $SIG{ALRM} = sub { $stop->(); exit 142; };
           my %number = (HUP => 1, INT => 2, TERM => 15);
           for my $name (keys %number) { $SIG{$name} = sub { $stop->(); exit 128 + $number{$name}; }; }
           alarm $seconds; waitpid($pid, 0); alarm 0;
           exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);' "${seconds}" "${pidfile}" "$@" < /dev/null
}

# ============================================================================================
# Inside the VM (`test_mac.sh --in-vm <op> <run id> ...`). Never on this Mac: every op first checks
# kern.hv_vmm_present. The run folder is ~/ntk/runs/<run id> (sources, DerivedData, results, logs).
# ============================================================================================

in_vm_main() {
  local op="$1" run_id="$2"; shift 2
  [[ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" == "1" ]] || { echo "Error: --in-vm runs only in the VM" >&2; exit 96; }
  [[ "${run_id}" =~ ${RUN_ID_PATTERN} ]] || { echo "Error: malformed run id" >&2; exit 96; }
  RUNS="${HOME}/ntk/runs"
  RUN_DIR="${RUNS}/${run_id}"
  SRC="${RUN_DIR}/src/mac"
  DD_UI="${RUN_DIR}/dd-ui"
  DD_LIB="${RUN_DIR}/dd-lib"
  RES="${RUN_DIR}/results"
  LOGS="${RUN_DIR}/logs"
  FX="/private/tmp/ntk-uitest-${run_id}"
  STATE="${HOME}/ntk/state"
  TESTS_DIR="${SRC}/MacLibraryExample/MacLibraryExampleUITests"
  vrunner() { /usr/bin/python3 "${RUN_DIR}/runner/mac_ui_runner.py" "$@"; }
  mkdir -p "${RES}" "${LOGS}" "${STATE}"
  case "${op}" in
    clean) vm_clean "${run_id}" ;;
    build) vm_build ;;
    enumerate) vm_enumerate ;;
    check-build) vm_check_build ;;
    prepare) vm_prepare ;;
    unit) vm_unit "$1" ;;
    ui) vm_ui "$1" ;;
    privacy-begin) vm_privacy_begin ;;
    privacy-end) vm_privacy_end ;;
    coverage) vm_coverage ;;
    finish) vm_finish "${1:-0}" ;;
    *) echo "Error: unknown op ${op}" >&2; exit 2 ;;
  esac
}

vm_restart_notification_ui() {  # 6b: NotificationCenter and usernoted, then 5 s once both are back
  killall NotificationCenter usernoted 2>/dev/null || true
  local i
  for i in $(seq 1 60); do
    pgrep -x NotificationCenter >/dev/null && pgrep -x usernoted >/dev/null && break
    sleep 0.5
  done
  sleep 5
  echo "NTK-VM restart notificationUI"
}

vm_stop_sample() {
  pkill -x MacLibraryExample 2>/dev/null || true
  local i
  for i in $(seq 1 40); do pgrep -x MacLibraryExample >/dev/null || return 0; sleep 0.25; done
  return 1
}

vm_unregister_outside() {  # U-21 (VM): every registered copy of the sample and the runner outside this run
  local dump="${LOGS}/lsregister.txt" path
  "${LSREGISTER}" -dump > "${dump}" 2>/dev/null || true
  vrunner lsregister --dump "${dump}" --run-root "${RUN_DIR}" --paths | while IFS= read -r path; do
    "${LSREGISTER}" -u "${path}" >/dev/null 2>&1 || true
    echo "NTK-VM unregistered a copy outside this run"
  done
  rm -f "${dump}"
}

vm_clean() {  # the previous runs: their processes, the preview setting they may have left, their folders
  local current="$1" folder
  pkill -x xcodebuild 2>/dev/null || true
  vm_stop_sample || true
  pkill -x Mail 2>/dev/null || true
  # Processes started from a previous run's folder (not this run's, which runs this script).
  local pid
  for pid in $(pgrep -f "${RUNS}/" || true); do
    ps -o args= -p "${pid}" 2>/dev/null | grep -qF "${RUNS}/${current}" || kill "${pid}" 2>/dev/null || true
  done
  if [[ -f "${STATE}/privacy-original" ]]; then
    # A run stopped inside the paste privacy stage: put the setting back as it was before it.
    if [[ "$(cat "${STATE}/privacy-original")" == "absent" ]]; then
      defaults delete "${SAMPLE_ID}" "${PREVIEW_KEY}" >/dev/null 2>&1 || true
    fi
    rm -f "${STATE}/privacy-original"
    echo "NTK-VM restored the paste privacy setting a stopped run left"
  fi
  for folder in "${RUNS}"/*; do
    [[ -d "${folder}" && "$(basename "${folder}")" != "${current}" ]] || continue
    rm -rf "${folder}"
    echo "NTK-VM removed a previous run folder"
  done
  rm -rf /private/tmp/ntk-uitest-* 2>/dev/null || true
  echo "NTK-VM clean"
}

vm_build() {
  local scheme dd log
  cd "${SRC}"
  for scheme in MacLibraryExample MacLibrary; do
    if [[ "${scheme}" == MacLibrary ]]; then dd="${DD_LIB}"; else dd="${DD_UI}"; fi
    log="${LOGS}/build-${scheme}.log"
    if ! capped_group 2400 - xcodebuild build-for-testing -workspace MacWorkspace.xcworkspace -scheme "${scheme}" \
        -destination "${DESTINATION}" -derivedDataPath "${dd}" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
        DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= > "${log}" 2>&1; then
      echo "NTK-VM build failed ${scheme} errors=$(grep -c ' error: ' "${log}" || true)"
      exit 1
    fi
    if [[ "$(ls "${dd}"/Build/Products/*.xctestrun 2>/dev/null | wc -l | tr -d ' ')" != "1" ]]; then
      echo "NTK-VM build failed ${scheme}: not exactly one .xctestrun"
      exit 1
    fi
    echo "NTK-VM build ok ${scheme} warnings=$(grep ' warning: ' "${log}" | grep -v appintentsmetadataprocessor | sort -u | wc -l | tr -d ' ')"
  done
}

xctestrun_of() { ls "$1"/Build/Products/*.xctestrun; }

vm_enumerate() {
  rm -rf "${RES}/enumerate.xcresult" "${RUN_DIR}/enumeration.json"
  if ! capped_group 600 - xcodebuild test-without-building -xctestrun "$(xctestrun_of "${DD_UI}")" \
      -destination "${DESTINATION}" -enumerate-tests -test-enumeration-style flat -test-enumeration-format json \
      -test-enumeration-output-path "${RUN_DIR}/enumeration.json" -resultBundlePath "${RES}/enumerate.xcresult" \
      > "${LOGS}/enumerate.log" 2>&1; then
    echo "NTK-VM enumerate failed" >&2
    exit 1
  fi
  cat "${RUN_DIR}/enumeration.json"
}

vm_check_build() {
  local products="${DD_UI}/Build/Products/Debug" binary
  binary="${products}/${UI_XCTEST_BINARY}"
  xcrun otool -arch arm64 -ov "${binary}" > "${LOGS}/otool-ov.txt"
  xcrun otool -arch arm64 -l "${binary}" > "${LOGS}/otool-l.txt"
  vrunner check-build --products "${products}" --tests-dir "${TESTS_DIR}" --enumeration "${RUN_DIR}/enumeration.json" \
    --otool-objc "${LOGS}/otool-ov.txt" --otool-load "${LOGS}/otool-l.txt"
}

vm_prepare() {
  # U-20: banners show while XCUITest records the screen.
  /usr/bin/python3 - <<'PY'
import os, plistlib
p = os.path.expanduser("~/Library/Preferences/com.apple.ncprefs.plist")
d = plistlib.load(open(p, "rb"))
dp = plistlib.loads(d["dnd_prefs"])
dp["dndMirrored"] = False
d["dnd_prefs"] = plistlib.dumps(dp, fmt=plistlib.FMT_BINARY)
plistlib.dump(d, open(p, "wb"), fmt=plistlib.FMT_BINARY)
PY
  killall cfprefsd 2>/dev/null || true
  vm_restart_notification_ui
  vm_stop_sample || true
  pkill -x Mail 2>/dev/null || true
  vm_unregister_outside
  # U-11: the fixture, and its manifest before the run.
  rm -rf "${FX}"
  mkdir -p "${FX}/dirA" "${FX}/dirB"
  echo a > "${FX}/a.txt"; echo b > "${FX}/b.txt"; echo '# note' > "${FX}/note.md"; echo default > "${FX}/default.txt"
  /usr/bin/python3 -c "import base64,sys;open(sys.argv[1],'wb').write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='))" "${FX}/pic.png"
  vrunner fixture-manifest --dir "${FX}" > "${RUN_DIR}/fixture-before.json"
  vrunner copy-mark --app "${DD_UI}/Build/Products/Debug/MacLibraryExample.app" > "${RUN_DIR}/expected-copy.txt"
  echo "NTK-VM prepared"
}

vm_xcresult_json() {  # <bundle> <out prefix>
  xcrun xcresulttool get test-results tests --path "$1" > "$2-tests.json" 2>/dev/null || rm -f "$2-tests.json"
  xcrun xcresulttool get test-results summary --path "$1" > "$2-summary.json" 2>/dev/null || rm -f "$2-summary.json"
}

vm_unit() {
  local index="$1" target xctestrun code=0 args
  target="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["unitInvocations"][int(sys.argv[2])]["target"])' "${RUN_DIR}/plan.json" "${index}")"
  if [[ "${target}" == MacLibraryTests ]]; then xctestrun="$(xctestrun_of "${DD_LIB}")"; else xctestrun="$(xctestrun_of "${DD_UI}")"; fi
  args="$(vrunner only-testing --plan "${RUN_DIR}/plan.json" --unit "${index}")"
  rm -rf "${RES}/unit-${index}.xcresult"
  # shellcheck disable=SC2086
  capped_group 1800 - xcodebuild test-without-building -xctestrun "${xctestrun}" -destination "${DESTINATION}" \
    ${args} -resultBundlePath "${RES}/unit-${index}.xcresult" -parallel-testing-enabled NO \
    > "${LOGS}/unit-${index}.log" 2>&1 || code=$?
  vm_xcresult_json "${RES}/unit-${index}.xcresult" "${RES}/unit-${index}"
  vrunner unit-record --target "${target}" --tests-json "${RES}/unit-${index}-tests.json" --exit-code "${code}" \
    --tests-dir "${TESTS_DIR}"
}

vm_reset_permission() {  # U-7 (VM): the sample stopped, its entry gone from com.apple.ncprefs, up to 3 tries
  vm_stop_sample || true
  local attempt
  for attempt in 1 2 3; do
    /usr/bin/python3 - "${SAMPLE_ID}" <<'PY'
import os, plistlib, sys
p = os.path.expanduser("~/Library/Preferences/com.apple.ncprefs.plist")
d = plistlib.load(open(p, "rb"))
d["apps"] = [a for a in d.get("apps", []) if a.get("bundle-id") != sys.argv[1]]
plistlib.dump(d, open(p, "wb"), fmt=plistlib.FMT_BINARY)
PY
    killall cfprefsd usernoted NotificationCenter 2>/dev/null || true
    sleep 2
    if ! defaults read com.apple.ncprefs apps 2>/dev/null | grep -qF "${SAMPLE_ID}"; then
      echo "NTK-VM permission reset attempt=${attempt}"
      return 0
    fi
  done
  echo "NTK-VM permission reset failed"
  return 1
}

vm_ui() {
  local index="$1" line stage name timeout prepare after class code=0 timed_out=0 args failed
  line="$(vrunner invocations --plan "${RUN_DIR}/plan.json" | awk -F'\t' -v i="${index}" '$1 == i')"
  IFS=$'\t' read -r _ stage name timeout prepare after class <<< "${line}"
  case ",${prepare}," in *,ncreset,*) vm_reset_permission || true ;; esac
  case ",${prepare}," in *,ncui,*) vm_restart_notification_ui ;; esac
  args="$(vrunner only-testing --plan "${RUN_DIR}/plan.json" --index "${index}")"
  rm -rf "${RES}/ui-${index}.xcresult"
  # shellcheck disable=SC2086
  TEST_RUNNER_NTK_HOST=vm \
  TEST_RUNNER_NTK_ALLOW="notification,ncsettings,settings,badge,clipboard,pasteprivacy,sharepicker,realservice,panels,coldstart" \
  TEST_RUNNER_NTK_FIXTURE_DIR="${FX}" TEST_RUNNER_NTK_EXPECTED_COPY="$(cat "${RUN_DIR}/expected-copy.txt")" \
    capped_group "${timeout}" - xcodebuild test-without-building -xctestrun "$(xctestrun_of "${DD_UI}")" \
    -destination "${DESTINATION}" ${args} -resultBundlePath "${RES}/ui-${index}.xcresult" "${TIME_FLAGS[@]}" \
    > "${LOGS}/ui-${index}.log" 2>&1 || code=$?
  [[ "${code}" == 142 ]] && timed_out=1
  vm_xcresult_json "${RES}/ui-${index}.xcresult" "${RES}/ui-${index}"
  vrunner record --plan "${RUN_DIR}/plan.json" --index "${index}" --tests-json "${RES}/ui-${index}-tests.json" \
    --summary-json "${RES}/ui-${index}-summary.json" --exit-code "${code}" --timed-out "${timed_out}" \
    --tests-dir "${TESTS_DIR}" | tee "${RES}/ui-${index}.records"
  failed=0
  grep -q '"result": "failed"' "${RES}/ui-${index}.records" && failed=1
  case "${class}" in
    NotificationPermissionUITests|NotificationUITests|NotificationEventUITests|NotificationColdStartUITests)
      # 6b: a notification test that failed may leave a banner expanded in the list; restart before the next.
      [[ "${failed}" == 1 ]] && vm_restart_notification_ui ;;
  esac
  case ",${after}," in *,stopMail,*) pkill -x Mail 2>/dev/null || true ;; esac
  vm_stop_sample || true
}

vm_privacy_begin() {  # U-12: the preview setting of the sample, and what it was before
  vm_stop_sample || true
  if defaults read "${SAMPLE_ID}" "${PREVIEW_KEY}" >/dev/null 2>&1; then
    echo "NTK-VM privacy setting already present; not starting the stage"
    exit 1
  fi
  echo absent > "${STATE}/privacy-original"
  defaults write "${SAMPLE_ID}" "${PREVIEW_KEY}" -bool yes
  echo "NTK-VM privacy begin"
}

vm_privacy_end() {
  vm_stop_sample || true
  defaults delete "${SAMPLE_ID}" "${PREVIEW_KEY}" >/dev/null 2>&1 || true
  if defaults read "${SAMPLE_ID}" "${PREVIEW_KEY}" >/dev/null 2>&1; then
    echo '{"test": "MacLibraryExampleUITests#privacyRestore", "result": "failed", "codes": ["NTK-RUNNER:privacyRestore"]}'
    exit 1
  fi
  rm -f "${STATE}/privacy-original"
  echo '{"test": "MacLibraryExampleUITests#privacyRestore", "result": "passed", "codes": []}'
}

vm_coverage() {
  local bundle n=0
  rm -rf "${RES}/attachments"
  mkdir -p "${RES}/attachments"
  for bundle in "${RES}"/ui-*.xcresult; do
    [[ -d "${bundle}" ]] || continue
    n=$((n + 1))
    xcrun xcresulttool export attachments --path "${bundle}" --output-path "${RES}/attachments/${n}" >/dev/null 2>&1 || true
  done
  vrunner coverage --plan "${RUN_DIR}/plan.json" --sample-dir "${SRC}/MacLibraryExample/MacLibraryExample" \
    --attachments-root "${RES}/attachments"
}

vm_finish() {
  local keep="$1" app
  # Only a run that prepared the fixture compares it (an enumeration for this Mac's plan did not).
  if [[ -f "${RUN_DIR}/fixture-before.json" ]]; then
    if [[ -d "${FX}" ]] && vrunner fixture-manifest --dir "${FX}" > "${RUN_DIR}/fixture-after.json"; then
      vrunner fixture-compare --before "${RUN_DIR}/fixture-before.json" --after "${RUN_DIR}/fixture-after.json"
    else
      echo '{"test": "MacLibraryExampleUITests#fixture", "result": "failed", "codes": ["NTK-RUNNER:fixture"]}'
    fi
  fi
  vm_stop_sample || true
  pkill -x Mail 2>/dev/null || true
  for app in "${DD_UI}/Build/Products/Debug/MacLibraryExample.app" \
             "${DD_UI}/Build/Products/Debug/MacLibraryExampleUITests-Runner.app"; do
    [[ -d "${app}" ]] && "${LSREGISTER}" -u "${app}" >/dev/null 2>&1 || true
  done
  rm -rf "${FX}"
  if [[ "${keep}" == 1 ]]; then
    echo "NTK-VM kept the run folder"
  else
    rm -rf "${RUN_DIR}"
    echo "NTK-VM removed the run folder"
  fi
}

if [[ "${1:-}" == "--in-vm" ]]; then
  shift
  in_vm_main "$@"
  exit 0
fi

# ============================================================================================
# On this Mac.
# ============================================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DIR="${ROOT_DIR}/mac"
TESTS_DIR="${MAC_DIR}/MacLibraryExample/MacLibraryExampleUITests"
PBXPROJ="${MAC_DIR}/MacLibraryExample/MacLibraryExample.xcodeproj/project.pbxproj"
OUT_ROOT="${MAC_DIR}/MacLibraryExample/build/test_mac"
BASELINE_DIR="${ROOT_DIR}/scripts"
ACCOUNT_HOME="$(python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
VM_KEYS="${ACCOUNT_HOME}/.tart/ntk-ssh"
MAC_XCODE_DIR="/Applications/Xcode26.6.app/Contents/Developer"

runner() { python3 "${ROOT_DIR}/scripts/mac_ui_runner.py" "$@"; }
fail() { echo "Error: $*" >&2; exit 1; }

WHERE=""; VM_NAME="ntk-macos-15-new"; FEATURE=""; SKIP_UNIT=0; ALLOW=""; ALLOW_LSREGISTER=0; DRY_RUN=0; APPROVED=""
BASELINE=0; NAME_EACH_TEST=0; QUALIFICATION=""; KEEP_VM_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --where) WHERE="${2:-}"; shift 2 ;;
    --vm) VM_NAME="${2:-}"; shift 2 ;;
    --feature) FEATURE="${2:-}"; shift 2 ;;
    --skip-unit) SKIP_UNIT=1; shift ;;
    --allow) ALLOW="${2-}"; shift 2 ;;
    --allow-lsregister) ALLOW_LSREGISTER=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --approved) APPROVED="${2:-}"; shift 2 ;;
    --baseline) BASELINE=1; shift ;;
    --name-each-test) NAME_EACH_TEST=1; shift ;;
    --qualification) QUALIFICATION="${2:-}"; shift 2 ;;
    --keep-vm-run) KEEP_VM_RUN=1; shift ;;
    *) fail "unknown option $1 (see the header of scripts/test_mac.sh)" ;;
  esac
done

[[ "${WHERE}" == vm || "${WHERE}" == mac ]] || fail "--where vm|mac is required (design 6.3)"
[[ "${VM_NAME}" =~ ^[A-Za-z0-9._-]+$ ]] || fail "malformed --vm"
case "${FEATURE}" in ""|Dialog|Notification|Share|Clipboard) ;; *) fail "--feature must be Dialog, Notification, Share or Clipboard" ;; esac
case "${QUALIFICATION}" in ""|mac26|mac26-reply|vm-ja) ;; *) fail "--qualification must be mac26, mac26-reply or vm-ja" ;; esac
if [[ "${WHERE}" == vm ]]; then
  [[ -z "${ALLOW}" && "${ALLOW_LSREGISTER}" == 0 && "${DRY_RUN}" == 0 && -z "${APPROVED}" ]] || \
    fail "--allow, --allow-lsregister, --dry-run and --approved are for --where mac"
  [[ -z "${QUALIFICATION}" || "${QUALIFICATION}" == vm-ja ]] || fail "--qualification ${QUALIFICATION} runs on this Mac"
else
  [[ "${NAME_EACH_TEST}" == 0 && "${KEEP_VM_RUN}" == 0 ]] || fail "--name-each-test and --keep-vm-run are for --where vm"
  [[ -z "${QUALIFICATION}" || "${QUALIFICATION}" != vm-ja ]] || fail "--qualification vm-ja runs in the VM"
  if [[ "${DRY_RUN}" == 1 ]]; then
    [[ -z "${APPROVED}" ]] || fail "--dry-run and --approved go to separate runs"
  else
    [[ -n "${APPROVED}" ]] || fail "this Mac runs only with --approved <file> (run --dry-run first and ask the user)"
  fi
fi
[[ -z "${FEATURE}" ]] || SKIP_UNIT=1
UNIT=1; [[ "${SKIP_UNIT}" == 1 ]] && UNIT=0
[[ -n "${QUALIFICATION}" ]] && UNIT=0

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(python3 -c 'import secrets; print(secrets.token_hex(3))')"
OUT="${OUT_ROOT}/${RUN_ID}-${WHERE}"
mkdir -p "${OUT}"
chmod 700 "${OUT}"
RESULTS="${OUT}/results.jsonl"
: > "${RESULTS}"
echo "[run] ${RUN_ID} (${WHERE})"

# --- The VM: qualification, identity and the commands sent to it ------------------------------

VM_IP=""; VM_UUID=""

vm_ssh_raw() {
  ssh -i "${VM_KEYS}/id_ed25519" -o UserKnownHostsFile="${VM_KEYS}/known_hosts" -o StrictHostKeyChecking=yes \
    -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=10 \
    -o LogLevel=ERROR "admin@${VM_IP}" "$@"
}

# Every command after the qualification first checks that the VM is the one that was qualified
# (its IOPlatformUUID; 6.3 "同一性の束ね").
vm_ssh() {
  vm_ssh_raw "u=\$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'\"' '/IOPlatformUUID/{print \$4}'); \
[ \"\$u\" = '${VM_UUID}' ] || { echo 'Error: the VM is not the one that was qualified' >&2; exit 96; }; $*"
}

vm_op() {  # <op> <run id> [args...]: the in-VM half of this script (stdin is not the caller's)
  vm_ssh "bash \"\$HOME/ntk/runs/${RUN_ID}/runner/test_mac.sh\" --in-vm $*" < /dev/null
}

json_lines() { grep '^{' "$1" || true; }

vm_qualify() {
  local facts="${OUT}/.vm-facts.txt" ps_out="${OUT}/.ps.txt"
  [[ -f "${VM_KEYS}/id_ed25519" && -f "${VM_KEYS}/known_hosts" ]] || fail "the VM's own ssh key and known_hosts are missing"
  tart list --format json > /dev/null 2>&1 || fail "tart is not available"
  VM_IP="$(tart ip "${VM_NAME}" 2>/dev/null)" || fail "the VM ${VM_NAME} is not running (tart ip)"
  [[ "${VM_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "unexpected address of the VM"
  ps -axo args= > "${ps_out}"
  vm_ssh_raw 'bash -s' > "${facts}" <<'EOS'
echo "hvVmmPresent=$(sysctl -n kern.hv_vmm_present 2>/dev/null)"
echo "hwModel=$(sysctl -n hw.model 2>/dev/null)"
echo "osVersion=$(sw_vers -productVersion)"
echo "osBuild=$(sw_vers -buildVersion)"
if defaults read MobileMeAccounts Accounts >/dev/null 2>&1; then echo "mobileMeAccounts=present"; else echo "mobileMeAccounts=absent"; fi
sqlite3 -separator '|' "$HOME/Library/Accounts/Accounts4.sqlite" \
  "select t.ZIDENTIFIER, a.ZAUTHENTICATED from ZACCOUNT a left join ZACCOUNTTYPE t on a.ZACCOUNTTYPE = t.Z_PK;" 2>/dev/null \
  | sed 's/^/account=/'
echo "virtiofsMounts=$(mount | grep -c virtiofs)"
xcodebuild -version 2>/dev/null | awk 'NR==1{print "xcodeVersion="$2} NR==2{print "xcodeBuild="$3}'
echo "language=$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p | tr -d ' ",')"
echo "platformUUID=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')"
echo "arch=$(uname -m)"
EOS
  python3 - "${facts}" "${OUT}/.vm-facts.json" <<'PY'
import json, sys
facts = {"accounts": []}
for line in open(sys.argv[1], encoding="utf-8"):
    key, _, value = line.rstrip("\n").partition("=")
    if key == "account":
        kind, _, authenticated = value.partition("|")
        facts["accounts"].append({"type": kind, "authenticated": authenticated})
    elif key:
        facts[key] = value
json.dump(facts, open(sys.argv[2], "w"))
PY
  runner vm-qualify --facts "${OUT}/.vm-facts.json" --ps "${ps_out}" --vm "${VM_NAME}" --out "${OUT}/vm-qualification.json" \
    --uuid-out "${OUT}/.vm-uuid" --qualification "${QUALIFICATION}"
  VM_UUID="$(cat "${OUT}/.vm-uuid")"
  VM_OS="$(python3 -c 'import json,sys; f=json.load(open(sys.argv[1])); print(f["osVersion"], f["osBuild"], f["arch"], f["language"], f["xcodeVersion"], sep="\t")' "${OUT}/.vm-facts.json")"
  rm -f "${facts}" "${ps_out}" "${OUT}/.vm-facts.json" "${OUT}/.vm-uuid"
}

vm_push() {  # 6.3 step 1: mac/ as git would hand it over, and the runner, by tar over ssh
  local list="${OUT}/.files"
  vm_ssh "mkdir -p \"\$HOME/ntk/runs/${RUN_ID}/src\" \"\$HOME/ntk/runs/${RUN_ID}/runner\""
  python3 - "${ROOT_DIR}" > "${list}" <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/scripts")
import mac_ui_runner as r
sys.stdout.write("".join(name + "\0" for name in r.git_file_list(sys.argv[1], ["mac"])))
PY
  (cd "${ROOT_DIR}" && COPYFILE_DISABLE=1 tar --null -T "${list}" -cf -) | \
    vm_ssh "tar -xf - -C \"\$HOME/ntk/runs/${RUN_ID}/src\""
  (cd "${ROOT_DIR}/scripts" && COPYFILE_DISABLE=1 tar -cf - mac_ui_runner.py test_mac.sh) | \
    vm_ssh "tar -xf - -C \"\$HOME/ntk/runs/${RUN_ID}/runner\""
  echo "[vm] handed over $(tr -cd '\0' < "${list}" | wc -c | tr -d ' ') files of mac/ and the runner"
  rm -f "${list}"
}

vm_send_plan() {
  vm_ssh "cat > \"\$HOME/ntk/runs/${RUN_ID}/plan.json\"" < "$1"
}

vm_enumeration() {  # 6.3 steps 0-3 in the VM: qualification, hand-over, build, enumeration
  vm_qualify
  vm_push
  vm_op clean "${RUN_ID}" | grep '^NTK-VM' | sed 's/^/  /'
  echo "[vm] building (Xcode 26.3, ad-hoc)"
  vm_op build "${RUN_ID}" | sed 's/^/  /'
  vm_op enumerate "${RUN_ID}" > "${OUT}/enumeration.json"
}

vm_cleanup_on_exit() {
  local code=$?
  if [[ -n "${VM_UUID}" && "${VM_FINISHED:-0}" != 1 ]]; then
    vm_op finish "${RUN_ID}" "${KEEP_VM_RUN}" 2>/dev/null | grep '^NTK-VM' | sed 's/^/  /' || true
  fi
  exit "${code}"
}

# --- The VM way --------------------------------------------------------------------------------

run_vm() {
  local head mac_tree index stage name timeout prepare after class stopped="" restarts=0 status plan="${OUT}/plan.json"
  runner check-sources --tests-dir "${TESTS_DIR}" --pbxproj "${PBXPROJ}"
  head="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
  mac_tree="$(runner tree-hash --repo "${ROOT_DIR}")"
  if [[ "${BASELINE}" == 1 && -n "$(git -C "${ROOT_DIR}" status --porcelain=v1 -uall -- mac | grep -v ' mac/MacLibraryExample/build/' || true)" ]]; then
    fail "--baseline needs mac/ without uncommitted changes"
  fi
  trap vm_cleanup_on_exit EXIT
  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
  vm_enumeration
  IFS=$'\t' read -r VM_OS_VERSION VM_OS_BUILD VM_ARCH VM_LANGUAGE VM_XCODE <<< "${VM_OS}"
  runner preflight --where vm --enumeration "${OUT}/enumeration.json" --tests-dir "${TESTS_DIR}" --repo "${ROOT_DIR}" \
    --feature "${FEATURE}" --qualification "${QUALIFICATION}" --os-major "${VM_OS_VERSION%%.*}" \
    --os-version "${VM_OS_VERSION}" --head "${head}" --mac-tree "${mac_tree}" --unit "${UNIT}" --plan "${plan}" \
    --baseline-dir "${BASELINE_DIR}" $([[ "${NAME_EACH_TEST}" == 1 ]] && echo --name-each-test)
  vm_send_plan "${plan}"
  vm_op check-build "${RUN_ID}" | sed 's/^/  /'
  vm_op prepare "${RUN_ID}" | grep '^NTK-VM' | sed 's/^/  /'
  # Unit tests (6.3 step 5).
  local count
  count="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["unitInvocations"]))' "${plan}")"
  for ((index = 0; index < count; index++)); do
    echo "[unit] ${index}"
    vm_op unit "${RUN_ID}" "${index}" | runner accept --results "${RESULTS}"
  done
  # The permission stage, the classes, the paste privacy stage (6.3 steps 6-8).
  while IFS=$'\t' read -r index stage name timeout prepare after class; do
    if [[ -n "${stopped}" ]]; then
      continue
    fi
    if [[ ",${prepare}," == *,privacy,* ]]; then
      vm_op privacy-begin "${RUN_ID}" | sed 's/^/  /'
    fi
    echo "[ui ${index}] ${stage} ${name}"
    vm_op ui "${RUN_ID}" "${index}" > "${OUT}/.ui.out" || true
    grep '^NTK-VM' "${OUT}/.ui.out" | sed 's/^/  /' || true
    restarts=$((restarts + $(grep -c '^NTK-VM restart' "${OUT}/.ui.out" || true)))
    json_lines "${OUT}/.ui.out" | runner accept --results "${RESULTS}"
    status="$(json_lines "${OUT}/.ui.out" | grep -c '"result": "failed"' || true)"
    rm -f "${OUT}/.ui.out"
    if [[ ",${prepare}," == *,privacy,* ]]; then
      vm_op privacy-end "${RUN_ID}" | runner accept --results "${RESULTS}"
    fi
    if [[ "${stage}" == watch && "${status}" != 0 ]]; then
      # U-20: the watch failed; the rest of the UI tests do not run and count as failures.
      echo "[watch] the watch N4 failed: the premise or the banner path does not hold; the remaining UI tests are not run"
      runner not-run --plan "${plan}" --from-index "$((index + 1))" --kind watchStopped | runner accept --results "${RESULTS}"
      stopped=watch
    fi
  done < <(runner invocations --plan "${plan}")
  if [[ -z "${FEATURE}" && -z "${QUALIFICATION}" && -z "${stopped}" ]]; then
    vm_op coverage "${RUN_ID}" | runner accept --results "${RESULTS}"
  fi
  VM_FINISHED=1
  vm_op finish "${RUN_ID}" "${KEEP_VM_RUN}" > "${OUT}/.finish.out" || true
  grep '^NTK-VM' "${OUT}/.finish.out" | sed 's/^/  /' || true
  json_lines "${OUT}/.finish.out" | runner accept --results "${RESULTS}"
  rm -f "${OUT}/.finish.out"
  python3 - "${OUT}/environment.json" "${OUT}/vm-qualification.json" "${VM_OS_VERSION}" "${VM_OS_BUILD}" "${VM_ARCH}" \
    "${VM_LANGUAGE}" "${VM_XCODE}" "${restarts}" <<'PY'
import json, sys
q = json.load(open(sys.argv[2]))
q["notificationUIRestarts"] = int(sys.argv[8])
env = {"where": "vm", "os": sys.argv[3], "osBuild": sys.argv[4], "arch": sys.argv[5], "language": sys.argv[6],
       "xcode": sys.argv[7], "signing": "adhoc", "vm": q}
json.dump(env, open(sys.argv[1], "w"), indent=2)
PY
  echo "[vm] notification UI restarts: ${restarts}"
  local code=0
  runner summary --plan "${plan}" --environment "${OUT}/environment.json" --results "${RESULTS}" \
    --baseline-dir "${BASELINE_DIR}" --repo "${ROOT_DIR}" $([[ "${BASELINE}" == 1 ]] && echo --save-baseline) || code=$?
  echo "[out] the public results: mac/MacLibraryExample/build/test_mac/${RUN_ID}-vm/"
  return "${code}"
}

# --- This Mac ------------------------------------------------------------------------------------

MAC_TMP=""
MAC_PIDFILE=""

# Before any xcodebuild on this Mac: the approved plan, the ledger, the runner and the tree (R-19).
mac_gate() {
  runner gate --plan "${MAC_TMP}/plan.approved.json" --approved "${MAC_TMP}/approval.approved.json" --repo "${ROOT_DIR}" \
    || exit 97
}

# Runs one xcodebuild on this Mac in its own group, records it as a writer in the run's marker, and
# waits. The gate runs first, every time.
mac_xcodebuild() {  # <seconds> <log> <xcodebuild arguments...>
  local seconds="$1" log="$2"; shift 2
  mac_gate
  rm -f "${MAC_PIDFILE}"
  DEVELOPER_DIR="${MAC_XCODE_DIR}" capped_group "${seconds}" "${MAC_PIDFILE}" xcodebuild "$@" > "${log}" 2>&1 &
  local waiter=$! i
  for i in $(seq 1 100); do [[ -s "${MAC_PIDFILE}" ]] && break; sleep 0.1; done
  if [[ -s "${MAC_PIDFILE}" ]]; then
    runner marker --root "${MAC_TMP}" --pid "$(cat "${MAC_PIDFILE}")" --role xcodebuild --group || true
  fi
  local code=0
  wait "${waiter}" || code=$?
  return "${code}"
}

# The order of 6.3 step 4: the xcodebuild group (TERM, 30 s, KILL), the sample and the runner started
# from this run's folder, this run's registrations, then the folder. A folder that cannot be removed
# is reported without its place.
mac_cleanup() {
  local code=$?
  trap - EXIT INT TERM HUP
  if [[ -n "${MAC_TMP}" && -d "${MAC_TMP}" ]]; then
    if [[ -s "${MAC_PIDFILE}" ]]; then
      local pid
      pid="$(cat "${MAC_PIDFILE}")"
      kill -TERM "-${pid}" 2>/dev/null || true
      for _ in $(seq 1 60); do kill -0 "-${pid}" 2>/dev/null || break; sleep 0.5; done
      kill -KILL "-${pid}" 2>/dev/null || true
    fi
    pkill -TERM -f "${MAC_TMP}/" 2>/dev/null || true
    sleep 1
    pkill -KILL -f "${MAC_TMP}/" 2>/dev/null || true
    local app
    for app in "${MAC_TMP}/dd-ui/Build/Products/Debug/MacLibraryExample.app" \
               "${MAC_TMP}/dd-ui/Build/Products/Debug/MacLibraryExampleUITests-Runner.app"; do
      [[ -d "${app}" ]] && "${LSREGISTER}" -u "${app}" >/dev/null 2>&1 || true
    done
    if ! rm -rf "${MAC_TMP}"; then
      echo "Error: the run's private temporary folder could not be removed (its place is not shown)" >&2
      code=1
    fi
  fi
  if [[ -n "${VM_UUID}" && "${VM_FINISHED:-0}" != 1 ]]; then
    VM_FINISHED=1
    vm_op finish "${RUN_ID}" 0 2>/dev/null | grep '^NTK-VM' | sed 's/^/  /' || true
  fi
  exit "${code}"
}

run_mac() {
  local head mac_tree os_version plan="${OUT}/plan.json" approval_out="${OUT}/approval.json"
  local lsreg="${OUT}/.lsregister.json" stale="${OUT}/.stale.json" scan_root="${TMPDIR:-/tmp}"
  scan_root="${scan_root%/}"
  # Step 0: read-only checks of this Mac.
  os_version="$(sw_vers -productVersion)"
  [[ "${os_version%%.*}" == 26 ]] || fail "this Mac is not macOS 26"
  [[ -d "${MAC_XCODE_DIR}" ]] || fail "Xcode 26.6 is not at /Applications/Xcode26.6.app (U-23)"
  runner check-sources --tests-dir "${TESTS_DIR}" --pbxproj "${PBXPROJ}"
  head="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
  mac_tree="$(runner tree-hash --repo "${ROOT_DIR}")"
  # Step 1: the enumeration comes from the VM (the same tree).
  trap vm_cleanup_on_exit EXIT
  vm_enumeration
  VM_FINISHED=1
  vm_op finish "${RUN_ID}" 0 | grep '^NTK-VM' | sed 's/^/  /' || true
  trap - EXIT
  # The previous runs of this Mac that a crash may have left (6.3 step 4), and the registered copies
  # of the sample (U-21; only when coldstart is allowed). Both read only; the raw lists stay private.
  runner stale --scan-root "${scan_root}" --list --out "${stale}"
  echo '[]' > "${lsreg}"
  if [[ ",${ALLOW}," == *,coldstart,* ]]; then
    local dumpdir
    dumpdir="$(umask 077; mktemp -d "${scan_root}/ntk-lsdump.XXXXXX")"
    "${LSREGISTER}" -dump > "${dumpdir}/dump.txt" 2>/dev/null || true
    runner lsregister --dump "${dumpdir}/dump.txt" --repo-root "${ROOT_DIR}" \
      --derived-root "${ACCOUNT_HOME}/Library/Developer/Xcode/DerivedData" --out "${lsreg}"
    rm -rf "${dumpdir}"
  fi
  if [[ "${DRY_RUN}" == 1 ]]; then
    runner preflight --where mac --enumeration "${OUT}/enumeration.json" --tests-dir "${TESTS_DIR}" --repo "${ROOT_DIR}" \
      --allow "${ALLOW}" --feature "${FEATURE}" --qualification "${QUALIFICATION}" --os-major "${os_version%%.*}" \
      --os-version "${os_version}" --head "${head}" --mac-tree "${mac_tree}" --unit "${UNIT}" --plan "${plan}" \
      --baseline-dir "${BASELINE_DIR}" --lsregister "${lsreg}" --stale "${stale}" --dry-run --approval-out "${approval_out}"
    if [[ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "${lsreg}")" != 0 && "${ALLOW_LSREGISTER}" == 0 ]]; then
      echo "[dry-run] coldstart: extra copies are registered; the run will stop unless they are removed (--allow-lsregister, its own approval)"
    fi
    echo "[dry-run] the approval list: mac/MacLibraryExample/build/test_mac/${RUN_ID}-mac/approval.json"
    rm -f "${lsreg}" "${stale}"
    return 0
  fi
  [[ -f "${APPROVED}" ]] || fail "the approval file does not exist"
  [[ "${ALLOW_LSREGISTER}" == 0 ]] || fail "--allow-lsregister is not implemented yet: remove extra copies by hand, then plan again"
  runner preflight --where mac --enumeration "${OUT}/enumeration.json" --tests-dir "${TESTS_DIR}" --repo "${ROOT_DIR}" \
    --allow "${ALLOW}" --feature "${FEATURE}" --qualification "${QUALIFICATION}" --os-major "${os_version%%.*}" \
    --os-version "${os_version}" --head "${head}" --mac-tree "${mac_tree}" --unit "${UNIT}" --plan "${plan}" \
    --baseline-dir "${BASELINE_DIR}" --lsregister "${lsreg}" --stale "${stale}" > /dev/null
  runner approve --plan "${plan}" --approved "${APPROVED}" --repo "${ROOT_DIR}"
  # Step 4: the private folder, its marker and the trap, before the first xcodebuild.
  MAC_TMP="$(umask 077; mktemp -d "${scan_root}/ntk-test-mac.XXXXXX")"
  MAC_TMP="$(cd -P "${MAC_TMP}" && pwd -P)"
  MAC_PIDFILE="${MAC_TMP}/xcodebuild.pid"
  trap mac_cleanup EXIT
  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
  runner marker --root "${MAC_TMP}" --run-id "${RUN_ID}"
  cp "${plan}" "${MAC_TMP}/plan.approved.json"; chmod 0444 "${MAC_TMP}/plan.approved.json"
  cp "${APPROVED}" "${MAC_TMP}/approval.approved.json"; chmod 0444 "${MAC_TMP}/approval.approved.json"
  plan="${MAC_TMP}/plan.approved.json"
  runner stale --scan-root "${scan_root}" --current-root "${MAC_TMP}"
  # Step 5: the build of this Mac (Xcode 26.6, the project's automatic signing; U-23, U-31).
  echo "[mac] building (Xcode 26.6)"
  mac_xcodebuild 2400 "${MAC_TMP}/build-ui.log" build-for-testing -workspace "${MAC_DIR}/MacWorkspace.xcworkspace" \
    -scheme MacLibraryExample -destination "${DESTINATION}" -derivedDataPath "${MAC_TMP}/dd-ui" \
    || fail "the build failed (the log stays private)"
  local products="${MAC_TMP}/dd-ui/Build/Products/Debug" binary
  binary="${products}/${UI_XCTEST_BINARY}"
  xcrun otool -arch arm64 -ov "${binary}" > "${MAC_TMP}/otool-ov.txt"
  xcrun otool -arch arm64 -l "${binary}" > "${MAC_TMP}/otool-l.txt"
  runner check-build --products "${products}" --tests-dir "${TESTS_DIR}" --enumeration "${OUT}/enumeration.json" \
    --otool-objc "${MAC_TMP}/otool-ov.txt" --otool-load "${MAC_TMP}/otool-l.txt"
  # Step 6: coldstart counts the registered copies again; any is a stop (U-21).
  if [[ ",${ALLOW}," == *,coldstart,* ]]; then
    "${LSREGISTER}" -dump > "${MAC_TMP}/lsregister.txt" 2>/dev/null || true
    runner lsregister --dump "${MAC_TMP}/lsregister.txt" --run-root "${MAC_TMP}" --repo-root "${ROOT_DIR}" \
      --derived-root "${ACCOUNT_HOME}/Library/Developer/Xcode/DerivedData" --out "${MAC_TMP}/lsregister.json"
    [[ "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "${MAC_TMP}/lsregister.json")" == 0 ]] \
      || fail "extra registered copies of the sample; not running coldstart (U-21)"
  fi
  # Step 7: the fixture (panels).
  local fx="/private/tmp/ntk-uitest-${RUN_ID}"
  if [[ ",${ALLOW}," == *,panels,* ]]; then
    (umask 077; mkdir -p "${fx}/dirA" "${fx}/dirB")
    echo a > "${fx}/a.txt"; echo b > "${fx}/b.txt"; echo '# note' > "${fx}/note.md"; echo default > "${fx}/default.txt"
    python3 -c "import base64,sys;open(sys.argv[1],'wb').write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='))" "${fx}/pic.png"
    runner fixture-manifest --dir "${fx}" > "${MAC_TMP}/fixture-before.json"
  fi
  local expected_copy
  expected_copy="$(runner copy-mark --app "${products}/MacLibraryExample.app")"
  local xctestrun
  xctestrun="$(ls "${MAC_TMP}"/dd-ui/Build/Products/*.xctestrun)"
  # Step 8: the audited unit tests only (U-29).
  local count index
  count="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["unitInvocations"]))' "${plan}")"
  if [[ "${count}" != 0 ]]; then
    mac_xcodebuild 2400 "${MAC_TMP}/build-lib.log" build-for-testing -workspace "${MAC_DIR}/MacWorkspace.xcworkspace" \
      -scheme MacLibrary -destination "${DESTINATION}" -derivedDataPath "${MAC_TMP}/dd-lib" || fail "the library build failed"
    for ((index = 0; index < count; index++)); do
      local code=0
      # shellcheck disable=SC2046
      mac_xcodebuild 1800 "${MAC_TMP}/unit-${index}.log" test-without-building \
        -xctestrun "$(ls "${MAC_TMP}"/dd-lib/Build/Products/*.xctestrun)" -destination "${DESTINATION}" \
        $(runner only-testing --plan "${plan}" --unit "${index}") -resultBundlePath "${MAC_TMP}/unit-${index}.xcresult" \
        -collect-test-diagnostics never || code=$?
      xcrun xcresulttool get test-results tests --path "${MAC_TMP}/unit-${index}.xcresult" > "${MAC_TMP}/unit-${index}-tests.json" 2>/dev/null || true
      runner unit-record --target MacLibraryTests --tests-json "${MAC_TMP}/unit-${index}-tests.json" --exit-code "${code}" \
        --tests-dir "${TESTS_DIR}" | runner accept --results "${RESULTS}"
    done
  fi
  # Step 9: the UI tests one by one; the watch first; a notification test that fails stops the rest.
  local stage name timeout prepare after class stop_kind=""
  while IFS=$'\t' read -r index stage name timeout prepare after class; do
    [[ -z "${stop_kind}" ]] || continue
    echo "[ui ${index}] ${name}"
    local code=0 timed_out=0
    # shellcheck disable=SC2046
    TEST_RUNNER_NTK_HOST=mac TEST_RUNNER_NTK_ALLOW="${ALLOW}" TEST_RUNNER_NTK_FIXTURE_DIR="${fx}" \
    TEST_RUNNER_NTK_EXPECTED_COPY="${expected_copy}" \
      mac_xcodebuild "${timeout}" "${MAC_TMP}/ui-${index}.log" test-without-building -xctestrun "${xctestrun}" \
      -destination "${DESTINATION}" $(runner only-testing --plan "${plan}" --index "${index}") \
      -resultBundlePath "${MAC_TMP}/ui-${index}.xcresult" "${TIME_FLAGS[@]}" -collect-test-diagnostics never || code=$?
    [[ "${code}" == 142 ]] && timed_out=1
    case "$(cd "$(dirname "${MAC_TMP}/ui-${index}.xcresult")" && pwd -P)" in
      "${MAC_TMP}") ;;
      *) fail "the result bundle is not in this run's folder" ;;
    esac
    xcrun xcresulttool get test-results tests --path "${MAC_TMP}/ui-${index}.xcresult" > "${MAC_TMP}/ui-${index}-tests.json" 2>/dev/null || rm -f "${MAC_TMP}/ui-${index}-tests.json"
    xcrun xcresulttool get test-results summary --path "${MAC_TMP}/ui-${index}.xcresult" > "${MAC_TMP}/ui-${index}-summary.json" 2>/dev/null || rm -f "${MAC_TMP}/ui-${index}-summary.json"
    local rcode=0
    runner record --plan "${plan}" --index "${index}" --tests-json "${MAC_TMP}/ui-${index}-tests.json" \
      --summary-json "${MAC_TMP}/ui-${index}-summary.json" --exit-code "${code}" --timed-out "${timed_out}" \
      --tests-dir "${TESTS_DIR}" > "${MAC_TMP}/ui-${index}.records" || rcode=$?
    runner accept --results "${RESULTS}" < "${MAC_TMP}/ui-${index}.records"
    rm -rf "${MAC_TMP}/ui-${index}.xcresult" "${MAC_TMP}/ui-${index}-tests.json" "${MAC_TMP}/ui-${index}-summary.json"
    [[ "${rcode}" == 0 ]] || fail "the results are not exactly the named tests; stopping (design 6.3 step 9)"
    if grep -q '"result": "failed"' "${MAC_TMP}/ui-${index}.records"; then
      if [[ "${stage}" == watch ]]; then stop_kind=watchStopped
      elif [[ "${class}" == Notification* ]]; then stop_kind=notificationStopped; fi
      if [[ -n "${stop_kind}" ]]; then
        echo "[stop] ${stop_kind}: Notification Center may still be open; close it, then plan and ask again for the rest"
        runner not-run --plan "${plan}" --from-index "$((index + 1))" --kind "${stop_kind}" | runner accept --results "${RESULTS}"
      fi
    fi
  done < <(runner invocations --plan "${plan}")
  # Step 10: what is left on this Mac, the fixture, the summary.
  if [[ -f "${MAC_TMP}/fixture-before.json" ]]; then
    runner fixture-manifest --dir "${fx}" > "${MAC_TMP}/fixture-after.json"
    runner fixture-compare --before "${MAC_TMP}/fixture-before.json" --after "${MAC_TMP}/fixture-after.json" \
      | runner accept --results "${RESULTS}"
    rm -rf "${fx}"
  fi
  echo "[mac] left on this Mac: the test strings on the pasteboard (clipboard), the category sample-category and badge 0"
  echo "      (notification, badge), System Settings or Finder brought to the front; this run's registrations were removed"
  python3 - "${OUT}/environment.json" "${os_version}" "$(sw_vers -buildVersion)" "$(uname -m)" \
    "$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p | tr -d ' ",')" \
    "$(DEVELOPER_DIR="${MAC_XCODE_DIR}" xcodebuild -version | awk 'NR==1{print $2}')" <<'PY'
import json, sys
env = {"where": "mac", "os": sys.argv[2], "osBuild": sys.argv[3], "arch": sys.argv[4], "language": sys.argv[5],
       "xcode": sys.argv[6], "signing": "team"}
json.dump(env, open(sys.argv[1], "w"), indent=2)
PY
  local code=0
  runner summary --plan "${plan}" --environment "${OUT}/environment.json" --results "${RESULTS}" \
    --baseline-dir "${BASELINE_DIR}" --repo "${ROOT_DIR}" --approved "${MAC_TMP}/approval.approved.json" \
    $([[ "${BASELINE}" == 1 ]] && echo --save-baseline) || code=$?
  return "${code}"
}

if [[ "${WHERE}" == vm ]]; then
  run_vm
else
  run_mac
fi
