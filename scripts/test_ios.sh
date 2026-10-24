#!/usr/bin/env bash
# Runs the iOS unit tests and the sample's UI tests on one simulator or one device.
#
# Follows section 6.3 of artifact/topics/ios-c-abi/designs/2026-10-18-ios-c-abi-ui-test-design.md.
# What runs and every check of what ran is decided in scripts/ios_ui_runner.py; this script runs
# xcodebuild, simctl and devicectl.
#
# Usage: scripts/test_ios.sh --udid <id> [--enumerate-udid <simulator>] [--devicectl-id <id>]
#          [--feature Dialog|Notification|Share|Clipboard] [--skip-unit] [--device-allow <c,...>]
#          [--dry-run] [--approved <file>] [--baseline] [--name-each-test]
#   --udid            a simulator listed by `xcrun simctl list`; any other value is the device
#                     (its hardware UDID)
#   --enumerate-udid  the simulator that is built for and enumerated (required for the device)
#   --devicectl-id    the device's devicectl identifier (device runs that are not --dry-run)
#   --feature         only that feature's UI classes and the common ones; no unit tests
#   --skip-unit       no unit tests (they only ever run on a simulator)
#   --device-allow    categories allowed on the device (none by default):
#                     systemui,sharesheet,clipboard,files,reinstall,credentials
#   --dry-run         builds and enumerates on the simulator, lists what would run and, for the
#                     device, writes the approval list; never touches the device
#   --approved        the approval list the user approved; required to run on the device, and an
#                     approval runs once
#   --baseline        saves the results as the baseline (a full run without failures, in one of
#                     the two environments of README D-21)
#   --name-each-test  on a simulator, names every test with -only-testing as the device does
#                     (the device always does)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="${ROOT_DIR}/ios"
WORKSPACE="${IOS_DIR}/IosWorkspace.xcworkspace"
TESTS_DIR="${IOS_DIR}/IosLibraryExample/IosLibraryExampleUITests"
SAMPLE_DIR="${IOS_DIR}/IosLibraryExample/IosLibraryExample"
PBXPROJ="${IOS_DIR}/IosLibraryExample/IosLibraryExample.xcodeproj/project.pbxproj"
BUILD_ROOT="${IOS_DIR}/IosLibraryExample/build/test_ios"
BUNDLE_ID="com.jonghyunkim.ios.nativetoolkit.example"
UI_XCTEST="IosLibraryExampleUITests-Runner.app/PlugIns/IosLibraryExampleUITests.xctest/IosLibraryExampleUITests"
BASELINE_DIR="${NTK_TEST_IOS_BASELINE_DIR:-${ROOT_DIR}/scripts}"

# What a test may touch on the device reaches it only through the device xcodebuild (U-9).
unset TEST_RUNNER_NTK_DEVICE_ALLOW NTK_DEVICE_ALLOW

runner() { python3 "${ROOT_DIR}/scripts/ios_ui_runner.py" "$@"; }

# Runs a command with a time limit; exit status 142 when it was cut off.
capped() {  # <seconds> <command...>
  local seconds="$1"; shift
  perl -e 'alarm shift; exec @ARGV or die "cannot run $ARGV[0]: $!\n"' "${seconds}" "$@"
}

# True when <path> is strictly inside <root>, both absolute, with no empty, "." or ".." component and
# no symlink at any level, and the part that exists is its own real path (`pwd -P`).
path_inside() {  # <root> <path>
  local root="$1" path="$2" prefix="" existing="/" part real
  [[ -n "${root}" && "${root}" == /* && "${path}" == "${root}/"?* ]] || return 1
  case "${path}/" in *//*|*/./*|*/../*|*$'\n'*) return 1 ;; esac
  local -a parts
  IFS=/ read -r -a parts <<< "${path#/}"
  for part in "${parts[@]}"; do
    prefix="${prefix}/${part}"
    [[ -L "${prefix}" ]] && return 1
    [[ -e "${prefix}" ]] && existing="${prefix}"
  done
  real="$(cd -P "${existing}" 2>/dev/null && pwd -P)" || return 1
  [[ "${real}" == "${existing}" ]]
}

# Every xcodebuild call but -version names its DerivedData, and a test action its result bundle,
# inside <root> (the run's output folder for the simulator, the device's results folder for the
# device), so that nothing lands in Xcode's default DerivedData or in another run's folder. Each
# option is given exactly once, as the two arguments `-option <value>`; `-option=<value>`, a
# missing value, a repeat or another spelling is refused. Returns 97 otherwise (first device run,
# stage 0d review of the fix: A-1, A-2).
require_own_paths() {  # <root> <xcodebuild arguments...>
  local root="$1"; shift
  [[ $# -eq 1 && "$1" == "-version" ]] && return 0
  local action="" derived="" bundle="" derived_count=0 bundle_count=0 action_count=0 argument lower expect=""
  for argument in "$@"; do
    if [[ -n "${expect}" ]]; then
      # The next argument is the value whatever it is; a missing value or another option is not a
      # path inside the root, so path_inside refuses it below.
      if [[ "${expect}" == "-derivedDataPath" ]]; then derived="${argument}"; else bundle="${argument}"; fi
      expect=""
      continue
    fi
    lower="$(printf '%s' "${argument}" | tr '[:upper:]' '[:lower:]')"
    case "${argument}" in
      -derivedDataPath) derived_count=$((derived_count + 1)); expect="${argument}"; continue ;;
      -resultBundlePath) bundle_count=$((bundle_count + 1)); expect="${argument}"; continue ;;
      # Every xcodebuild action word is counted, so a second action cannot ride on an allowed one
      # (stage 0d review of the fix: A-3).
      build-for-testing|test|test-without-building) action_count=$((action_count + 1)); action="${argument}" ;;
      build|analyze|archive|clean|install|installsrc|docbuild) action_count=$((action_count + 1)); action="${argument}" ;;
    esac
    if [[ "${lower}" == *deriveddatapath* || "${lower}" == *resultbundlepath* ]]; then
      echo "Error: xcodebuild option in a form this script does not allow: ${argument}" >&2; return 97
    fi
  done
  if [[ "${action_count}" -ne 1 ]]; then
    echo "Error: xcodebuild needs exactly one action, got ${action_count}" >&2; return 97
  fi
  case "${action}" in
    build-for-testing|test|test-without-building) ;;
    *) echo "Error: xcodebuild ${action} is not run; only build-for-testing, test or test-without-building" >&2; return 97 ;;
  esac
  if [[ "${derived_count}" -ne 1 ]] || ! path_inside "${root}" "${derived}"; then
    echo "Error: xcodebuild needs exactly one -derivedDataPath inside '${root}', got ${derived_count}: '${derived}'" >&2
    return 97
  fi
  if [[ "${action}" == "build-for-testing" ]]; then
    [[ "${bundle_count}" -eq 0 ]] && return 0
  fi
  if [[ "${bundle_count}" -ne 1 ]] || ! path_inside "${root}" "${bundle}"; then
    echo "Error: xcodebuild ${action} needs exactly one -resultBundlePath inside '${root}', got ${bundle_count}: '${bundle}'" >&2
    return 97
  fi
}

# Refuses any destination that is not a simulator by UDID (stage 0d review R-10): the device is
# reached only through device_xcodebuild.
sim_xcodebuild() {  # <seconds> <xcodebuild arguments...>
  local seconds="$1"; shift
  require_own_paths "${OUT_DIR:-}" "$@" || return 97
  local previous="" argument
  for argument in "$@"; do
    if [[ "${previous}" == "-destination" && "${argument}" != "platform=iOS Simulator,id="* ]]; then
      echo "Error: sim_xcodebuild refuses the destination ${argument}" >&2
      return 97
    fi
    case "${argument}" in
      -destination=*|-destination-timeout*) echo "Error: sim_xcodebuild refuses ${argument}" >&2; return 97 ;;
    esac
    previous="${argument}"
  done
  capped "${seconds}" env -u TEST_RUNNER_NTK_DEVICE_ALLOW -u NTK_DEVICE_ALLOW xcodebuild "$@" < /dev/null
}

# --- The device: approval first, then the cleanup trap, then the device (6.3 steps 3-4) -----------
DEVICE_TMP=""
DEVICE_TRAP_READY=0
APPROVAL_CONSUMED=0
DEVICE_ALLOW=""
PLAN=""
APPROVED=""

cleanup_device_tmp() {
  if [[ -n "${DEVICE_TMP}" && -e "${DEVICE_TMP}" ]]; then
    rm -rf "${DEVICE_TMP}" 2>/dev/null || true
    if [[ -e "${DEVICE_TMP}" ]]; then
      echo "Error: could not remove the device results at ${DEVICE_TMP}; remove that folder by hand" >&2
    fi
  fi
}

# Creates the folder for the device's result bundles and registers its removal before the first
# device xcodebuild (6.3 step 4). INT, TERM and HUP exit with their usual status so that the EXIT
# trap runs.
setup_device_tmp() {
  DEVICE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/test_ios-device.XXXXXX")"
  # Its real path (TMPDIR is under the /var symlink on macOS): xcodebuild paths inside it are
  # checked for symlinks (require_own_paths).
  DEVICE_TMP="$(cd -P "${DEVICE_TMP}" && pwd -P)"
  trap cleanup_device_tmp EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  DEVICE_TRAP_READY=1
}

# Before every call that reaches the device: the approval consumed, the trap set, and the
# approved plan, the runner and the tree unchanged (stage 0d review R-18, R-19).
device_guard() {
  if [[ "${DEVICE_TRAP_READY}" != 1 || "${APPROVAL_CONSUMED}" != 1 ]]; then
    echo "Error: refusing to touch the device before the approval is consumed and the cleanup trap is set" >&2
    return 97
  fi
  runner device-gate --plan "${PLAN}" --approved "${APPROVED}" --repo "${ROOT_DIR}" --tests-dir "${TESTS_DIR}" || return 97
}

device_xcodebuild() {  # <seconds> <xcodebuild arguments...>
  device_guard || return $?
  local seconds="$1"; shift
  require_own_paths "${DEVICE_TMP:-}" "$@" || return 97
  capped "${seconds}" env TEST_RUNNER_NTK_DEVICE_ALLOW="${DEVICE_ALLOW}" xcodebuild "$@" < /dev/null
}

device_devicectl() {  # <devicectl arguments...>
  device_guard || return $?
  capped 300 xcrun devicectl "$@" < /dev/null
}

# The self-tests (scripts/tests/test_ios_ui_runner.py) source the functions above and stop here.
# The variable works only when the file is sourced; a run with it set is refused, so a value left
# in the environment cannot turn a run into a silent exit 0.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  if [[ "${NTK_TEST_IOS_SOURCE_ONLY:-0}" == 1 ]]; then
    return 0
  fi
elif [[ -n "${NTK_TEST_IOS_SOURCE_ONLY:-}" ]]; then
  echo "Error: NTK_TEST_IOS_SOURCE_ONLY is for the self-tests that source this file; unset it to run" >&2
  exit 2
fi

usage() {
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
}

UDID=""
ENUMERATE_UDID=""
DEVICECTL_ID=""
FEATURE=""
SKIP_UNIT=0
DRY_RUN=0
APPROVED=""
SAVE_BASELINE=0
NAME_EACH_TEST=0
DEVICE_ALLOW_GIVEN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid) UDID="$2"; shift 2 ;;
    --enumerate-udid) ENUMERATE_UDID="$2"; shift 2 ;;
    --devicectl-id) DEVICECTL_ID="$2"; shift 2 ;;
    --feature) FEATURE="$2"; shift 2 ;;
    --skip-unit) SKIP_UNIT=1; shift ;;
    --device-allow) DEVICE_ALLOW="$2"; DEVICE_ALLOW_GIVEN=1; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --approved) APPROVED="$2"; shift 2 ;;
    --baseline) SAVE_BASELINE=1; shift ;;
    --name-each-test) NAME_EACH_TEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done
[[ -n "${UDID}" ]] || { echo "Error: --udid is required" >&2; exit 2; }
case "${FEATURE}" in
  ""|Dialog|Notification|Share|Clipboard) ;;
  *) echo "Error: --feature takes Dialog, Notification, Share or Clipboard" >&2; exit 2 ;;
esac
if [[ "${SAVE_BASELINE}" -eq 1 && ( -n "${FEATURE}" || "${SKIP_UNIT}" -eq 1 || "${DRY_RUN}" -eq 1 ) ]]; then
  echo "Error: --baseline needs a full run: drop --feature, --skip-unit and --dry-run" >&2; exit 2
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BUILD_ROOT}"
STAGE_DIR="$(mktemp -d "${BUILD_ROOT}/${STAMP}-pending.XXXXXX")"
xcrun simctl list -j devices > "${STAGE_DIR}/simctl-devices.json"
xcrun simctl list -j runtimes > "${STAGE_DIR}/simctl-runtimes.json"

# --- 0. Destination and environment ---------------------------------------------------------
KIND="$(runner destination --udid "${UDID}" --simctl-devices "${STAGE_DIR}/simctl-devices.json")"
if [[ "${KIND}" == "simulator" ]]; then
  if [[ "${DEVICE_ALLOW_GIVEN}" -eq 1 || -n "${APPROVED}" || -n "${DEVICECTL_ID}" ]]; then
    echo "Error: --device-allow, --approved and --devicectl-id are for the device; ${UDID} is a simulator" >&2; exit 2
  fi
else
  [[ -n "${ENUMERATE_UDID}" ]] || { echo "Error: ${UDID} is not a simulator, so it is the device: --enumerate-udid is required" >&2; exit 2; }
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    [[ -z "${APPROVED}" ]] || { echo "Error: --approved is not used with --dry-run" >&2; exit 2; }
  else
    [[ -n "${APPROVED}" ]] || { echo "Error: running on the device needs --approved (run --dry-run first and ask the user)" >&2; exit 2; }
    [[ -n "${DEVICECTL_ID}" ]] || { echo "Error: running on the device needs --devicectl-id" >&2; exit 2; }
  fi
fi
ENUM_UDID="$(runner enumeration-destination --kind "${KIND}" --udid "${UDID}" --enumerate-udid "${ENUMERATE_UDID}" \
  --simctl-devices "${STAGE_DIR}/simctl-devices.json")"
XCODE="$(xcodebuild -version | tr '\n' ' ' | sed 's/ *$//')"

if [[ "${KIND}" == "simulator" ]]; then
  LANGUAGE="$(plutil -extract AppleLanguages.0 raw -o - \
    "${HOME}/Library/Developer/CoreSimulator/Devices/${UDID}/data/Library/Preferences/.GlobalPreferences.plist" 2>/dev/null || echo unknown)"
  runner environment --kind simulator --udid "${UDID}" --simctl-devices "${STAGE_DIR}/simctl-devices.json" \
    --simctl-runtimes "${STAGE_DIR}/simctl-runtimes.json" --language "${LANGUAGE}" --xcode "${XCODE}" \
    --baseline-dir "${BASELINE_DIR}" --out "${STAGE_DIR}/environment.json"
  LABEL="$(python3 -c 'import json,sys; e=json.load(open(sys.argv[1])); print(e["model"].replace(" ", "_") + "-" + e["os"])' "${STAGE_DIR}/environment.json")"
  INITIAL_SIM_STATE="$(python3 -c 'import json,sys
for ds in json.load(open(sys.argv[1]))["devices"].values():
    for d in ds:
        if d["udid"] == sys.argv[2]: print(d["state"])' "${STAGE_DIR}/simctl-devices.json" "${UDID}")"
else
  LABEL="device"
  INITIAL_SIM_STATE=""
fi
OUT_DIR="${BUILD_ROOT}/${STAMP}-${LABEL}"
suffix=1
while [[ -e "${OUT_DIR}" ]]; do  # two runs in the same second
  OUT_DIR="${BUILD_ROOT}/${STAMP}-${LABEL}-${suffix}"
  suffix=$((suffix + 1))
done
mv "${STAGE_DIR}" "${OUT_DIR}"
# The real path: every xcodebuild path of the simulator must be inside it, without symlinks.
OUT_DIR="$(cd -P "${OUT_DIR}" && pwd -P)"
# The simulator build is made in the run's folder (no build is reused from another run).
DD_SIM="${OUT_DIR}/dd-build"
RESULTS="${OUT_DIR}/results.jsonl"
PLAN="${OUT_DIR}/plan.json"
: > "${RESULTS}"
echo "[out] ${OUT_DIR}"

# Leaves the simulator as it was found (xcodebuild boots it; the permission stage boots it too).
restore_simulator() {
  if [[ "${INITIAL_SIM_STATE}" == "Shutdown" ]]; then
    capped 120 xcrun simctl shutdown "${UDID}" >/dev/null 2>&1 || true
  fi
}
if [[ "${KIND}" == "simulator" ]]; then
  trap restore_simulator EXIT
fi

runner check-sources --tests-dir "${TESTS_DIR}" --pbxproj "${PBXPROJ}"

# --- 2a. Build for the enumeration simulator ------------------------------------------------
echo "[build] simulator ${ENUM_UDID}"
rm -f "${DD_SIM}"/Build/Products/*.xctestrun
sim_xcodebuild 3600 build-for-testing -workspace "${WORKSPACE}" -scheme IosLibraryExample \
  -destination "platform=iOS Simulator,id=${ENUM_UDID}" -derivedDataPath "${DD_SIM}" -quiet \
  > "${OUT_DIR}/build-simulator.log" 2>&1 || { echo "Error: the simulator build failed (${OUT_DIR}/build-simulator.log)" >&2; exit 1; }
XCTESTRUN_SIM="$(ls "${DD_SIM}"/Build/Products/*iphonesimulator*.xctestrun)"
[[ "$(echo "${XCTESTRUN_SIM}" | wc -l | tr -d ' ')" == 1 ]] || { echo "Error: expected one simulator .xctestrun" >&2; exit 1; }

# --- 1. Unit tests (the simulator only) --------------------------------------------------------
RUN_UNIT=0
[[ "${KIND}" == "simulator" && -z "${FEATURE}" && "${SKIP_UNIT}" -eq 0 && "${DRY_RUN}" -eq 0 ]] && RUN_UNIT=1
if [[ "${RUN_UNIT}" -eq 1 ]]; then
  for target in IosLibraryTests IosLibraryExampleTests; do
    echo "[unit] ${target}"
    bundle="${OUT_DIR}/unit-${target}.xcresult"
    set +e
    if [[ "${target}" == IosLibraryTests ]]; then
      sim_xcodebuild 1800 test -workspace "${WORKSPACE}" -scheme IosLibrary -destination "platform=iOS Simulator,id=${UDID}" \
        -derivedDataPath "${DD_SIM}" -parallel-testing-enabled NO -resultBundlePath "${bundle}" -quiet \
        > "${OUT_DIR}/unit-${target}.log" 2>&1
    else
      sim_xcodebuild 1800 test-without-building -xctestrun "${XCTESTRUN_SIM}" -destination "platform=iOS Simulator,id=${UDID}" \
        -derivedDataPath "${OUT_DIR}/dd-unit" -parallel-testing-enabled NO -only-testing:"${target}" -resultBundlePath "${bundle}" \
        > "${OUT_DIR}/unit-${target}.log" 2>&1
    fi
    code=$?
    set -e
    if [[ -d "${bundle}" ]]; then
      xcrun xcresulttool get test-results tests --path "${bundle}" > "${OUT_DIR}/unit-${target}-tests.json"
    fi
    runner unit-record --target "${target}" --tests-json "${OUT_DIR}/unit-${target}-tests.json" --exit-code "${code}" \
      --results "${RESULTS}"
  done
fi

# --- 2b. Enumerate on the simulator and check the declarations ---------------------------------
echo "[enumerate] simulator ${ENUM_UDID}"
sim_xcodebuild 600 test-without-building -xctestrun "${XCTESTRUN_SIM}" -destination "platform=iOS Simulator,id=${ENUM_UDID}" \
  -derivedDataPath "${OUT_DIR}/dd-enumerate" -resultBundlePath "${OUT_DIR}/enumerate.xcresult" \
  -enumerate-tests -test-enumeration-style flat -test-enumeration-format json \
  -test-enumeration-output-path "${OUT_DIR}/enumeration.json" > "${OUT_DIR}/enumerate.log" 2>&1 \
  || { echo "Error: the enumeration failed (${OUT_DIR}/enumerate.log)" >&2; exit 1; }
HEAD="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
APPROVAL_OUT="${OUT_DIR}/approval.json"
preflight_args=(--kind "${KIND}" --udid "${UDID}" --enumerate-udid "${ENUM_UDID}" --enumeration "${OUT_DIR}/enumeration.json"
  --tests-dir "${TESTS_DIR}" --products "${DD_SIM}/Build/Products" --feature "${FEATURE}" --allow "${DEVICE_ALLOW}"
  --head "${HEAD}" --unit "${RUN_UNIT}" --repo "${ROOT_DIR}" --plan "${PLAN}" --approval-out "${APPROVAL_OUT}")
[[ "${DRY_RUN}" -eq 1 ]] && preflight_args+=(--dry-run)
[[ "${NAME_EACH_TEST}" -eq 1 ]] && preflight_args+=(--name-each-test)
runner preflight "${preflight_args[@]}"

# --- 3. Stop here for --dry-run ----------------------------------------------------------------
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[dry-run] stopped before running any test; nothing was sent to a device"
  exit 0
fi

RESULT_ROOT="${OUT_DIR}"
XCTESTRUN="${XCTESTRUN_SIM}"
if [[ "${KIND}" == "device" ]]; then
  runner approve --plan "${PLAN}" --approved "${APPROVED}" --repo "${ROOT_DIR}" \
    --head "$(git -C "${ROOT_DIR}" rev-parse HEAD)" --tests-dir "${TESTS_DIR}"
  APPROVAL_CONSUMED=1
  # --- 4. The device: result folder and trap, environment, build, binary inventory -------------
  setup_device_tmp
  RESULT_ROOT="${DEVICE_TMP}"
  # The device build too is made inside the folder the trap removes.
  DD_DEVICE="${DEVICE_TMP}/dd-build"
  # From here on only a read-only copy of the approved plan is used; the gate checks its digest
  # before every device call (R-19).
  cp "${PLAN}" "${DEVICE_TMP}/plan.approved.json"
  chmod 0444 "${DEVICE_TMP}/plan.approved.json"
  PLAN="${DEVICE_TMP}/plan.approved.json"
  device_devicectl device info details --device "${DEVICECTL_ID}" --json-output "${DEVICE_TMP}/devicectl-info.json" >/dev/null
  runner environment --kind device --udid "${UDID}" --devicectl-json "${DEVICE_TMP}/devicectl-info.json" --xcode "${XCODE}" \
    --baseline-dir "${BASELINE_DIR}" --out "${OUT_DIR}/environment.json"
  runner verify-tree --plan "${PLAN}" --head "$(git -C "${ROOT_DIR}" rev-parse HEAD)" --tests-dir "${TESTS_DIR}" \
    --repo "${ROOT_DIR}"
  echo "[build] device"
  rm -f "${DD_DEVICE}"/Build/Products/*.xctestrun
  device_xcodebuild 3600 build-for-testing -workspace "${WORKSPACE}" -scheme IosLibraryExample \
    -destination "platform=iOS,id=${UDID}" -allowProvisioningUpdates -derivedDataPath "${DD_DEVICE}" -quiet \
    > "${DEVICE_TMP}/build-device.log" 2>&1 || { echo "Error: the device build failed" >&2; tail -20 "${DEVICE_TMP}/build-device.log" >&2; exit 1; }
  XCTESTRUN="$(ls "${DD_DEVICE}"/Build/Products/*iphoneos*.xctestrun)"
  [[ "$(echo "${XCTESTRUN}" | wc -l | tr -d ' ')" == 1 ]] || { echo "Error: expected one device .xctestrun" >&2; exit 1; }
  otool -ov "${DD_DEVICE}/Build/Products/Debug-iphoneos/${UI_XCTEST}" > "${DEVICE_TMP}/otool-objc.txt"
  otool -l "${DD_DEVICE}/Build/Products/Debug-iphoneos/${UI_XCTEST}" > "${DEVICE_TMP}/otool-load.txt"
  runner check-binary --plan "${PLAN}" --otool-objc "${DEVICE_TMP}/otool-objc.txt" --otool-load "${DEVICE_TMP}/otool-load.txt" \
    --tests-dir "${TESTS_DIR}" --products "${DD_DEVICE}/Build/Products"
fi

# --- 5-7. The permission stage, the classes, the CB2 stage -------------------------------------
runner invocations --plan "${PLAN}" > "${OUT_DIR}/invocations.tsv"
FULL_SIM_RUN=0
[[ "${KIND}" == "simulator" && -z "${FEATURE}" ]] && FULL_SIM_RUN=1
STOPPED=0
while IFS=$'\t' read -r -u 3 index stage name timeout uninstall; do
  [[ -n "${index}" ]] || continue
  echo "[${stage}] ${name}"
  if [[ "${uninstall}" == 1 ]]; then
    if [[ "${KIND}" == "simulator" ]]; then
      # xcodebuild leaves the simulator shut down; simctl uninstall needs it booted (0c notes 7.4).
      capped 300 xcrun simctl bootstatus "${UDID}" -b > /dev/null
      xcrun simctl uninstall "${UDID}" "${BUNDLE_ID}"
    else
      runner may-uninstall --plan "${PLAN}" --approved "${APPROVED}"
      device_devicectl device uninstall app --device "${DEVICECTL_ID}" "${BUNDLE_ID}" > /dev/null
    fi
  fi
  runner only-testing --plan "${PLAN}" --index "${index}" > "${OUT_DIR}/only-testing-${index}.txt"
  args=()
  while IFS= read -r argument; do args+=("${argument}"); done < "${OUT_DIR}/only-testing-${index}.txt"
  [[ "${#args[@]}" -gt 0 ]] || { echo "Error: no -only-testing for ${name}; not calling xcodebuild" >&2; exit 1; }
  safe_name="$(echo "${name}" | tr '/' '_')"
  bundle="${RESULT_ROOT}/${index}-${safe_name}.xcresult"
  log="${RESULT_ROOT}/${index}-${safe_name}.log"
  set +e
  if [[ "${KIND}" == "simulator" ]]; then
    sim_xcodebuild "${timeout}" test-without-building -xctestrun "${XCTESTRUN}" -destination "platform=iOS Simulator,id=${UDID}" \
      -derivedDataPath "${OUT_DIR}/dd-test" -parallel-testing-enabled NO -resultBundlePath "${bundle}" "${args[@]}" \
      > "${log}" 2>&1
  else
    # The run's own DerivedData and no diagnostics, inside the folder the trap removes (R-12).
    device_xcodebuild "${timeout}" test-without-building -xctestrun "${XCTESTRUN}" -destination "platform=iOS,id=${UDID}" \
      -derivedDataPath "${DEVICE_TMP}/dd-test" -collect-test-diagnostics never \
      -parallel-testing-enabled NO -resultBundlePath "${bundle}" "${args[@]}" > "${log}" 2>&1
  fi
  code=$?
  set -e
  timed_out=0
  [[ "${code}" -eq 142 ]] && timed_out=1
  tests_json="${RESULT_ROOT}/${index}-tests.json"
  summary_json="${RESULT_ROOT}/${index}-summary.json"
  rm -f "${tests_json}" "${summary_json}"
  if [[ -d "${bundle}" ]]; then
    xcrun xcresulttool get test-results tests --path "${bundle}" > "${tests_json}" || rm -f "${tests_json}"
    xcrun xcresulttool get test-results summary --path "${bundle}" > "${summary_json}" || rm -f "${summary_json}"
  fi
  set +e
  runner record --plan "${PLAN}" --index "${index}" --tests-json "${tests_json}" --summary-json "${summary_json}" \
    --exit-code "${code}" --timed-out "${timed_out}" --results "${RESULTS}"
  record_code=$?
  set -e
  if [[ "${record_code}" -eq 3 ]]; then
    STOPPED=1
    break
  elif [[ "${record_code}" -ne 0 ]]; then
    echo "Error: reading the results of ${name} failed" >&2; exit 1
  fi
  # Button coverage attachments (3.7): the simulator's full run only; never from the device.
  if [[ "${FULL_SIM_RUN}" -eq 1 && -d "${bundle}" ]]; then
    mkdir -p "${OUT_DIR}/attachments/${index}"
    xcrun xcresulttool export attachments --path "${bundle}" --output-path "${OUT_DIR}/attachments/${index}" > /dev/null
  fi
done 3< "${OUT_DIR}/invocations.tsv"

if [[ "${STOPPED}" -eq 1 ]]; then
  echo "Error: the device run was stopped: the results were not exactly the named tests" >&2
  exit 1
fi

# --- 8-9. Coverage, summary and baseline -------------------------------------------------------
if [[ "${FULL_SIM_RUN}" -eq 1 ]]; then
  runner coverage --plan "${PLAN}" --sample-dir "${SAMPLE_DIR}" --attachments-root "${OUT_DIR}/attachments" --results "${RESULTS}"
fi
summary_args=(--plan "${PLAN}" --environment "${OUT_DIR}/environment.json" --results "${RESULTS}" --baseline-dir "${BASELINE_DIR}")
[[ "${SAVE_BASELINE}" -eq 1 ]] && summary_args+=(--save-baseline)
[[ -n "${APPROVED}" ]] && summary_args+=(--approved "${APPROVED}")
runner summary "${summary_args[@]}"
