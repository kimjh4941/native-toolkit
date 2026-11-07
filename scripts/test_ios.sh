#!/usr/bin/env bash
# Runs the iOS unit tests and the sample's UI tests on one simulator or one device, or the C ABI's
# UI tests on one simulator (--capi-ui).
#
# Follows section 6.3 of artifact/topics/ios-c-abi/designs/2026-10-18-ios-c-abi-ui-test-design.md.
# What runs and every check of what ran is decided in scripts/ios_ui_runner.py; this script runs
# xcodebuild, simctl and devicectl.
#
# Usage: scripts/test_ios.sh --udid <id> [--enumerate-udid <simulator>] [--devicectl-id <id>]
#          [--feature Dialog|Notification|Share|Clipboard] [--skip-unit] [--device-allow <c,...>]
#          [--dry-run] [--approved <file>] [--baseline] [--name-each-test]
#        scripts/test_ios.sh --udid <simulator> --capi-ui
#        scripts/test_ios.sh --udid <simulator> --capi
#        scripts/test_ios.sh --udid <device> --enumerate-udid <simulator> --capi-device
#          (--dry-run | --approved <file> --devicectl-id <id>)
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
#   --capi-ui         only the UI tests of the C ABI (IosLibraryCApiUITests, C ABI design part 2,
#                     TB-2b and 12.2): a simulator only, and it takes no other option but --udid.
#                     Needs Xcode 26.6 through DEVELOPER_DIR. It restarts that simulator before every
#                     xcodebuild; nothing else may run on it during the run (there is no lock)
#   --capi            only the checks of the C ABI (C ABI design part 1, C-6; part 2, TB-12): a
#                     simulator only, and it takes no other option but --udid. Needs Xcode 26.6
#                     through DEVELOPER_DIR and Simulator.app closed. IosLibraryCApiTests without a
#                     sanitizer, with ASan and with TSan; a build of the distributable inside the
#                     run's folder (never dist/), check_ios_dist.py, check_c_abi_contract_ios.py with
#                     --library on each slice, --require-compile and --require-complete, and the smoke
#                     (run_ios_capi_smoke.sh, with its unsigned device build that is never installed).
#                     Every step runs and the summary decides; scripts/ios_capi_runner.py reads them
#   --capi-device     the device's checks of the C ABI (stage 2 working notes, 17; part 1, 6 P1-20; part 2,
#                     15.2): IosLibraryCApiTests with ASan on the device, then the smoke built from the
#                     distributable, signed, installed and launched on the device. The device only, Xcode
#                     26.6, and the same guards as the sample's device runs: --dry-run writes the approval
#                     list (with the tests that --enumerate-udid's simulator enumerates) and never reaches the
#                     device; --approved (with --devicectl-id, which must name the --udid device) runs it once.
#                     The test host and the smoke stay installed (removing an app needs its own approval)
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

# Runs a command in its own process group with a time limit. When the time is up, the whole group (the
# command and what it started, such as xcodebuild or simctl under a script) is killed, the command is
# reaped, and the exit status is 142; an interrupt (INT, TERM, HUP) kills the group the same way, as the
# terminal's Ctrl-C reaches only its foreground group; otherwise the command's own status. stdin is /dev/null, as the group
# is not the terminal's foreground group. The same form as scripts/run_ios_capi_smoke.sh (TB-12 review B).
capped_group() {  # <seconds> <command...>
  local seconds="$1"; shift
  perl -e 'my $seconds = shift; die "time limit: $seconds\n" unless $seconds =~ /^[1-9][0-9]*$/;
           my $pid = fork; die "fork: $!\n" unless defined $pid;
           if ($pid == 0) { setpgrp(0, 0); exec @ARGV or exit 127; }
           setpgrp($pid, $pid);
           $SIG{ALRM} = sub { kill "KILL", -$pid; waitpid($pid, 0); exit 142; };
           my %number = (HUP => 1, INT => 2, TERM => 15);
           for my $name (keys %number) {
             $SIG{$name} = sub { kill "KILL", -$pid; waitpid($pid, 0); exit 128 + $number{$name}; };
           }
           alarm $seconds; waitpid($pid, 0); alarm 0;
           exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);' "${seconds}" "$@" < /dev/null
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

# --- The device for --capi-device: the same flags, trap and folder as above; its own gate, as its approved
# plan is ios_capi_runner.py's (stage 2 working notes, 17.3).
capi_device_guard() {
  if [[ "${DEVICE_TRAP_READY}" != 1 || "${APPROVAL_CONSUMED}" != 1 ]]; then
    echo "Error: refusing to touch the device before the approval is consumed and the cleanup trap is set" >&2
    return 97
  fi
  python3 "${ROOT_DIR}/scripts/ios_capi_runner.py" device-gate --plan "${PLAN}" --approved "${APPROVED}" --repo "${ROOT_DIR}" || return 97
}
# Before each step that reaches the device or signs, outside the step's redirection so that a refusal is
# seen: a changed plan, runner or tree stops the run (the trap removes the device's folder).
capi_device_gate_or_stop() {
  capi_device_guard || { echo "Error: the device gate refused; nothing more reaches the device" >&2; exit 1; }
}
# The environment of every xcodebuild on the device path: nothing from outside the approved list may change the
# build or the tests (an xcconfig over the projects' settings, another toolchain, a TEST_RUNNER_ variable, which
# reaches the test host). Sets CAPI_DEVICE_ENV to an `env -u ...` prefix (ios_capi_runner.py DEVICE_ENV_REMOVED).
capi_device_env() {
  local name
  CAPI_DEVICE_ENV=(env -u XCODE_XCCONFIG_FILE -u TOOLCHAINS -u NTK_DEVICE_ALLOW)
  for name in $(compgen -e); do
    [[ "${name}" == TEST_RUNNER_* ]] && CAPI_DEVICE_ENV+=(-u "${name}")
  done
  return 0
}
capi_device_xcodebuild() {  # <seconds> <xcodebuild arguments...>: in its own group, so a cut-off kills it
  capi_device_guard || return $?
  local seconds="$1"; shift
  require_own_paths "${DEVICE_TMP:-}" "$@" || return 97
  capi_device_env
  capped_group "${seconds}" "${CAPI_DEVICE_ENV[@]}" xcodebuild "$@"
}
capi_device_devicectl() {  # <seconds> <devicectl arguments...>: in its own group, so a cut-off kills it
  capi_device_guard || return $?
  local seconds="$1"; shift
  capped_group "${seconds}" xcrun devicectl "$@"
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
  sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'
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
CAPI_UI=0
CAPI=0
CAPI_DEVICE=0
# Every option given but --udid, --capi and --capi-ui, whatever its value: --capi and --capi-ui refuse
# them even when the value is empty (TB-12 review B).
OTHER_OPTIONS=""
# An option that takes a value must have one that is not itself an option: `--udid --dry-run --udid <id>`
# would otherwise take --dry-run as the first value and hide it from the checks below.
needs_value() {  # <option> [<value>...]
  if [[ $# -lt 2 || "$2" == -* ]]; then
    echo "Error: $1 needs a value" >&2; exit 2
  fi
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid|--capi|--capi-ui|-h|--help) ;;
    *) OTHER_OPTIONS="${OTHER_OPTIONS} $1" ;;
  esac
  case "$1" in
    --udid) needs_value "$@"; UDID="$2"; shift 2 ;;
    --enumerate-udid) needs_value "$@"; ENUMERATE_UDID="$2"; shift 2 ;;
    --devicectl-id) needs_value "$@"; DEVICECTL_ID="$2"; shift 2 ;;
    --feature) needs_value "$@"; FEATURE="$2"; shift 2 ;;
    --skip-unit) SKIP_UNIT=1; shift ;;
    --device-allow) needs_value "$@"; DEVICE_ALLOW="$2"; DEVICE_ALLOW_GIVEN=1; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --approved) needs_value "$@"; APPROVED="$2"; shift 2 ;;
    --baseline) SAVE_BASELINE=1; shift ;;
    --name-each-test) NAME_EACH_TEST=1; shift ;;
    --capi-ui) CAPI_UI=1; shift ;;
    --capi) CAPI=1; shift ;;
    --capi-device) CAPI_DEVICE=1; shift ;;
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

# Whether an option was given, not its value: an empty --feature, --enumerate-udid, --approved or
# --devicectl-id is refused too.
if [[ "${CAPI_UI}" -eq 1 && ( -n "${OTHER_OPTIONS}" || "${CAPI}" -eq 1 ) ]]; then
  echo "Error: --capi-ui takes no other option but --udid (given:${OTHER_OPTIONS}$([[ "${CAPI}" -eq 1 ]] && echo " --capi"))" >&2; exit 2
fi
if [[ "${CAPI}" -eq 1 && -n "${OTHER_OPTIONS}" ]]; then
  echo "Error: --capi takes no other option but --udid (given:${OTHER_OPTIONS})" >&2; exit 2
fi
# --capi-device takes --udid, --enumerate-udid and either --dry-run alone or --approved with --devicectl-id; any
# other option, given with any value, is refused before anything runs.
if [[ "${CAPI_DEVICE}" -eq 1 ]]; then
  capi_device_given=" "
  for word in ${OTHER_OPTIONS}; do
    case "${word}" in
      --capi-device) ;;
      --enumerate-udid) ;;
      --dry-run|--approved|--devicectl-id) capi_device_given="${capi_device_given}${word} " ;;
      *) echo "Error: --capi-device takes --udid, --enumerate-udid and --dry-run, or --approved and --devicectl-id (given:${OTHER_OPTIONS})" >&2; exit 2 ;;
    esac
  done
  if [[ -z "${ENUMERATE_UDID}" ]]; then
    echo "Error: --capi-device needs --enumerate-udid <simulator>: the expected tests are its enumeration" >&2; exit 2
  fi
  if [[ "${capi_device_given}" == *" --dry-run "* ]]; then
    if [[ "${capi_device_given}" != " --dry-run " ]]; then
      echo "Error: --capi-device --dry-run takes neither --approved nor --devicectl-id" >&2; exit 2
    fi
  elif [[ "${capi_device_given}" != *" --approved "* || "${capi_device_given}" != *" --devicectl-id "* \
          || -z "${APPROVED}" || -z "${DEVICECTL_ID}" ]]; then
    echo "Error: --capi-device runs on the device only with --approved <file> and --devicectl-id <id> (run --dry-run first and ask the user)" >&2; exit 2
  fi
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BUILD_ROOT}"
STAGE_DIR="$(mktemp -d "${BUILD_ROOT}/${STAMP}-pending.XXXXXX")"
xcrun simctl list -j devices > "${STAGE_DIR}/simctl-devices.json"
xcrun simctl list -j runtimes > "${STAGE_DIR}/simctl-runtimes.json"

# --- 0. Destination and environment ---------------------------------------------------------
KIND="$(runner destination --udid "${UDID}" --simctl-devices "${STAGE_DIR}/simctl-devices.json")"
if [[ "${CAPI_UI}" -eq 1 && "${KIND}" != "simulator" ]]; then
  echo "Error: --capi-ui runs on a simulator only; ${UDID} is not one" >&2; exit 2
fi
# The device's ASan and smoke run only at the stage's end, each time with the user's approval
# (agent-rules/device-testing.md, P1-20); this option never reaches it.
if [[ "${CAPI}" -eq 1 && "${KIND}" != "simulator" ]]; then
  echo "Error: --capi runs on a simulator only; ${UDID} is not one" >&2; exit 2
fi
if [[ "${CAPI_DEVICE}" -eq 1 && "${KIND}" == "simulator" ]]; then
  echo "Error: --capi-device runs on the device only; ${UDID} is a simulator (use --capi)" >&2; exit 2
fi
if [[ "${KIND}" == "simulator" ]]; then
  if [[ "${DEVICE_ALLOW_GIVEN}" -eq 1 || -n "${APPROVED}" || -n "${DEVICECTL_ID}" ]]; then
    echo "Error: --device-allow, --approved and --devicectl-id are for the device; ${UDID} is a simulator" >&2; exit 2
  fi
elif [[ "${CAPI_DEVICE}" -eq 1 ]]; then
  :  # checked above: --enumerate-udid, and --dry-run alone or --approved with --devicectl-id
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
  [[ "${CAPI_DEVICE}" -eq 1 ]] && LABEL="capi-device"
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
    # Says so and never fails the run: this is a trap on EXIT, after the results.
    local state=unknown
    if capped 120 xcrun simctl list -j devices > "${OUT_DIR}/simctl-restore.json" 2>/dev/null; then
      state="$(runner capi-simulator-state --udid "${UDID}" --simctl-devices "${OUT_DIR}/simctl-restore.json" 2>/dev/null)" || state=unknown
    fi
    if [[ "${state}" != "Shutdown" ]]; then
      echo "Warning: ${UDID} was shut down before this run and is now ${state}" >&2
    fi
  fi
}
if [[ "${KIND}" == "simulator" ]]; then
  trap restore_simulator EXIT
fi

# --- The UI tests of the C ABI: their own project, plan and results; none of the sample's stages -----
if [[ "${CAPI_UI}" -eq 1 ]]; then
  runner capi-check-xcode --xcode "${XCODE}"
  if [[ "${INITIAL_SIM_STATE}" == "Booted" ]]; then
    echo "Warning: --capi-ui restarts ${UDID}, which is booted, before every xcodebuild; nothing else may run on it during this run" >&2
  fi
  CAPI_PROJECT="${IOS_DIR}/IosLibraryCApi/IosLibraryCApi.xcodeproj"
  CAPI_HEADERS="${IOS_DIR}/IosLibraryCApi/include/NativeToolkitC"
  CAPI_APP_DIR="${IOS_DIR}/IosLibraryCApiUITestApp"
  runner capi-check-sources --pbxproj "${CAPI_PROJECT}/project.pbxproj" \
    --framework-scheme "${CAPI_PROJECT}/xcshareddata/xcschemes/IosLibraryCApi.xcscheme" \
    --app-dir "${CAPI_APP_DIR}" --headers-dir "${CAPI_HEADERS}" --tests-dir "${IOS_DIR}/IosLibraryCApiUITests"
  CAPI_BUNDLE_ID="$(runner capi-bundle-id)"

  # Every run starts from a restart: a permission alert that a failed test left open survives the
  # deletion of its app and stops every later test until the simulator restarts (stage 2 working
  # notes, 5.4). The restart keeps the permissions, so it does not replace the deletion. simctl
  # shutdown fails on a simulator already shut down, so the state afterwards is what counts.
  capi_restart_simulator() {
    capped 120 xcrun simctl shutdown "${UDID}" > /dev/null 2>&1 || true
    capped 120 xcrun simctl list -j devices > "${OUT_DIR}/simctl-restart.json" \
      || { echo "Error: simctl list failed or timed out while restarting ${UDID}" >&2; exit 1; }
    local state
    state="$(runner capi-simulator-state --udid "${UDID}" --simctl-devices "${OUT_DIR}/simctl-restart.json")"
    if [[ "${state}" != "Shutdown" ]]; then
      echo "Error: ${UDID} did not shut down (state ${state}); a test would start without the restart" >&2; exit 1
    fi
    capped 300 xcrun simctl bootstatus "${UDID}" -b > /dev/null \
      || { echo "Error: ${UDID} did not boot (simctl bootstatus failed)" >&2; exit 1; }
  }

  echo "[build] simulator ${UDID}"
  sim_xcodebuild 3600 build-for-testing -workspace "${WORKSPACE}" -scheme IosLibraryCApiUITestApp \
    -destination "platform=iOS Simulator,id=${UDID}" -derivedDataPath "${DD_SIM}" -quiet \
    > "${OUT_DIR}/build-simulator.log" 2>&1 || { echo "Error: the simulator build failed (${OUT_DIR}/build-simulator.log)" >&2; exit 1; }
  XCTESTRUN="$(ls "${DD_SIM}"/Build/Products/*iphonesimulator*.xctestrun)"
  [[ "$(echo "${XCTESTRUN}" | wc -l | tr -d ' ')" == 1 ]] || { echo "Error: expected one simulator .xctestrun" >&2; exit 1; }
  CAPI_APP="${DD_SIM}/Build/Products/Debug-iphonesimulator/IosLibraryCApiUITestApp.app"
  : > "${OUT_DIR}/app-nm.txt"
  : > "${OUT_DIR}/app-otool.txt"
  CAPI_MAIN="${CAPI_APP}/IosLibraryCApiUITestApp"
  CAPI_DYLIB="${CAPI_APP}/IosLibraryCApiUITestApp.debug.dylib"
  [[ -f "${CAPI_MAIN}" ]] || { echo "Error: the built app has no executable: ${CAPI_MAIN}" >&2; exit 1; }
  nm -u "${CAPI_MAIN}" >> "${OUT_DIR}/app-nm.txt"
  otool -L "${CAPI_MAIN}" >> "${OUT_DIR}/app-otool.txt"
  # The app's own code is in the .debug.dylib of a Debug build, when the executable uses one.
  if grep -q "@rpath/IosLibraryCApiUITestApp.debug.dylib" "${OUT_DIR}/app-otool.txt" && [[ ! -f "${CAPI_DYLIB}" ]]; then
    echo "Error: the executable uses a debug dylib that is not there: ${CAPI_DYLIB}" >&2; exit 1
  fi
  if [[ -f "${CAPI_DYLIB}" ]]; then
    nm -u "${CAPI_DYLIB}" >> "${OUT_DIR}/app-nm.txt"
    otool -L "${CAPI_DYLIB}" >> "${OUT_DIR}/app-otool.txt"
  fi
  runner capi-check-binary --nm "${OUT_DIR}/app-nm.txt" --otool "${OUT_DIR}/app-otool.txt" \
    --app-dir "${CAPI_APP_DIR}" --headers-dir "${CAPI_HEADERS}"
  echo "[enumerate] simulator ${UDID}"
  sim_xcodebuild 600 test-without-building -xctestrun "${XCTESTRUN}" -destination "platform=iOS Simulator,id=${UDID}" \
    -resultBundlePath "${OUT_DIR}/enumerate.xcresult" -derivedDataPath "${OUT_DIR}/dd-enumerate" \
    -enumerate-tests -test-enumeration-style flat -test-enumeration-format json \
    -test-enumeration-output-path "${OUT_DIR}/enumeration.json" > "${OUT_DIR}/enumerate.log" 2>&1 \
    || { echo "Error: the enumeration failed (${OUT_DIR}/enumerate.log)" >&2; exit 1; }
  runner capi-plan --kind "${KIND}" --udid "${UDID}" --enumeration "${OUT_DIR}/enumeration.json" --plan "${PLAN}"
  runner invocations --plan "${PLAN}" > "${OUT_DIR}/invocations.tsv"
  while IFS=$'\t' read -r -u 3 index stage name timeout uninstall; do
    [[ -n "${index}" ]] || continue
    echo "[${stage}] ${name}"
    capi_restart_simulator
    if [[ "${uninstall}" == 1 ]]; then
      xcrun simctl uninstall "${UDID}" "${CAPI_BUNDLE_ID}" \
        || { echo "Error: could not delete ${CAPI_BUNDLE_ID} from ${UDID} (simctl uninstall failed)" >&2; exit 1; }
    fi
    runner capi-only-testing --plan "${PLAN}" --index "${index}" > "${OUT_DIR}/only-testing-${index}.txt"
    args=()
    while IFS= read -r argument; do args+=("${argument}"); done < "${OUT_DIR}/only-testing-${index}.txt"
    [[ "${#args[@]}" -gt 0 ]] || { echo "Error: no -only-testing for ${name}; not calling xcodebuild" >&2; exit 1; }
    safe_name="$(echo "${name}" | tr '/' '_')"
    bundle="${OUT_DIR}/${index}-${safe_name}.xcresult"
    set +e
    sim_xcodebuild "${timeout}" test-without-building -xctestrun "${XCTESTRUN}" -destination "platform=iOS Simulator,id=${UDID}" \
      -parallel-testing-enabled NO -derivedDataPath "${OUT_DIR}/dd-test" -resultBundlePath "${bundle}" "${args[@]}" \
      > "${OUT_DIR}/${index}-${safe_name}.log" 2>&1
    code=$?
    set -e
    timed_out=0
    [[ "${code}" -eq 142 ]] && timed_out=1
    tests_json="${OUT_DIR}/${index}-tests.json"
    summary_json="${OUT_DIR}/${index}-summary.json"
    rm -f "${tests_json}" "${summary_json}"
    if [[ -d "${bundle}" ]]; then
      xcrun xcresulttool get test-results tests --path "${bundle}" > "${tests_json}" || rm -f "${tests_json}"
      xcrun xcresulttool get test-results summary --path "${bundle}" > "${summary_json}" || rm -f "${summary_json}"
    fi
    runner capi-record --plan "${PLAN}" --index "${index}" --tests-json "${tests_json}" --summary-json "${summary_json}" \
      --exit-code "${code}" --timed-out "${timed_out}" --results "${RESULTS}"
  done 3< "${OUT_DIR}/invocations.tsv"
  runner capi-summary --plan "${PLAN}" --results "${RESULTS}"
  exit 0
fi

# --- The checks of the C ABI (part 1, C-6 and 6.1; part 2, TB-12): every step runs and is recorded,
# and the summary decides the exit status. None of the sample's stages; nothing reaches the device.
if [[ "${CAPI}" -eq 1 ]]; then
  capi_runner() { python3 "${ROOT_DIR}/scripts/ios_capi_runner.py" "$@"; }
  capi_runner check-xcode --xcode "${XCODE}"
  # Simulator.app syncs the simulator's pasteboard with the Mac's (agent-rules/device-testing.md). It is
  # never opened or closed here; an open one stops the run before each step that uses the simulator.
  capi_require_no_simulator_app() {
    local status=0
    pgrep -x Simulator > /dev/null || status=$?
    if [[ "${status}" -eq 0 ]]; then
      echo "Error: Simulator.app is open; close it and run again (agent-rules/device-testing.md)" >&2; exit 2
    elif [[ "${status}" -ne 1 ]]; then
      # Only "no process matched" (1) says that it is closed.
      echo "Error: pgrep failed (status ${status}); cannot tell whether Simulator.app is open" >&2; exit 2
    fi
  }
  capi_require_no_simulator_app
  CAPI_VERSION="$(capi_runner version --common-h "${IOS_DIR}/IosLibraryCApi/include/NativeToolkitC/Common.h")"
  CAPI_DIST="${OUT_DIR}/capi-dist"
  echo "[capi] library ${CAPI_VERSION}; results in ${RESULTS}"

  # 1. IosLibraryCApiTests without a sanitizer, with ASan and with TSan (they cannot be combined), each
  # in its own DerivedData so that the framework each loads is the one built for it.
  for variant in normal asan tsan; do
    echo "[capi-unit] ${variant}"
    capi_require_no_simulator_app
    sanitizer=()
    case "${variant}" in
      asan) sanitizer=(-enableAddressSanitizer YES) ;;
      tsan) sanitizer=(-enableThreadSanitizer YES) ;;
    esac
    dd="${OUT_DIR}/dd-capi-${variant}"
    bundle="${OUT_DIR}/capi-unit-${variant}.xcresult"
    log="${OUT_DIR}/capi-unit-${variant}.log"
    set +e
    sim_xcodebuild 3600 test -workspace "${WORKSPACE}" -scheme IosLibraryCApi -destination "platform=iOS Simulator,id=${UDID}" \
      -derivedDataPath "${dd}" -parallel-testing-enabled NO -only-testing:IosLibraryCApiTests -resultBundlePath "${bundle}" \
      ${sanitizer[@]+"${sanitizer[@]}"} > "${log}" 2>&1
    code=$?
    set -e
    timed_out=0
    [[ "${code}" -eq 142 ]] && timed_out=1
    summary_json="${OUT_DIR}/capi-unit-${variant}-summary.json"
    # The test host's standard error (where a sanitizer reports) is in the xcodebuild log and in the
    # bundle's action log; the bundle of a test run has no console log.
    action_log="${OUT_DIR}/capi-unit-${variant}-action.json"
    rm -f "${summary_json}" "${action_log}"
    if [[ -d "${bundle}" ]]; then
      xcrun xcresulttool get test-results summary --path "${bundle}" > "${summary_json}" || rm -f "${summary_json}"
      xcrun xcresulttool get log --type action --path "${bundle}" > "${action_log}" || rm -f "${action_log}"
    fi
    # What each framework loads says whether the variant's sanitizer measured it (part 1, 6.1).
    otool_args=()
    for framework in IosLibraryCApi IosLibrary; do
      binary="${dd}/Build/Products/Debug-iphonesimulator/${framework}.framework/${framework}"
      listing="${OUT_DIR}/capi-unit-${variant}-otool-${framework}.txt"
      if [[ -f "${binary}" ]] && otool -L "${binary}" > "${listing}"; then
        otool_args+=(--otool "${framework}" "${listing}")
      fi
    done
    capi_runner unit-record --variant "${variant}" --exit-code "${code}" --timed-out "${timed_out}" \
      --summary-json "${summary_json}" --log "test log" "${log}" --log "action log" "${action_log}" \
      ${otool_args[@]+"${otool_args[@]}"} --results "${RESULTS}"
  done

  # 2. The distributable, built inside this run's folder (never dist/) without touching the projects.
  echo "[capi-dist] build ${CAPI_VERSION} into ${CAPI_DIST}"
  set +e
  capped_group 3600 "${ROOT_DIR}/scripts/build_ios_library_xcframework.sh" -m IosLibrary -m IosLibraryCApi -v "${CAPI_VERSION}" \
    --output-dir "${CAPI_DIST}" --build-dir "${OUT_DIR}/capi-dist-build" --keep-project-versions \
    > "${OUT_DIR}/capi-dist-build.log" 2>&1
  code=$?
  set -e
  dist_built=0
  [[ "${code}" -eq 0 ]] && dist_built=1
  capi_runner step-record --step dist-build --exit-code "${code}" --timed-out "$([[ "${code}" -eq 142 ]] && echo 1 || echo 0)" \
    --log "${OUT_DIR}/capi-dist-build.log" --results "${RESULTS}"

  # 3. The distributable's own check, then the contract against each slice of the capi (README 7.3).
  if [[ "${dist_built}" -eq 1 ]]; then
    echo "[capi-dist] check_ios_dist.py"
    set +e
    python3 "${ROOT_DIR}/scripts/check_ios_dist.py" --dist "${CAPI_DIST}" > "${OUT_DIR}/capi-dist-check.log" 2>&1
    code=$?
    set -e
    capi_runner step-record --step dist-check --exit-code "${code}" --log "${OUT_DIR}/capi-dist-check.log" --results "${RESULTS}"
  else
    capi_runner step-record --step dist-check --not-run "the distributable was not built" --results "${RESULTS}"
  fi
  for entry in "ios-arm64:arm64" "ios-arm64_x86_64-simulator:arm64,x86_64"; do
    slice="${entry%%:*}"
    archs="${entry#*:}"
    binary="${CAPI_DIST}/ios-native-toolkit-capi-${CAPI_VERSION}.xcframework/${slice}/IosLibraryCApi.framework/IosLibraryCApi"
    if [[ "${dist_built}" -ne 1 ]]; then
      capi_runner step-record --step "contract-${slice}" --not-run "the distributable was not built" --results "${RESULTS}"
      continue
    fi
    if [[ ! -f "${binary}" ]]; then
      capi_runner step-record --step "contract-${slice}" --not-run "no ${binary}" --results "${RESULTS}"
      continue
    fi
    echo "[capi-contract] ${slice} (${archs})"
    set +e
    python3 "${ROOT_DIR}/scripts/check_c_abi_contract_ios.py" --require-compile --require-complete --library "${binary}" \
      --architectures "${archs}" > "${OUT_DIR}/capi-contract-${slice}.log" 2>&1
    code=$?
    set -e
    capi_runner step-record --step "contract-${slice}" --exit-code "${code}" --log "${OUT_DIR}/capi-contract-${slice}.log" \
      --results "${RESULTS}"
  done

  # 4. The smoke from the two xcframeworks alone, on this simulator; its device build is unsigned and
  # never installed (part 2, 12.4).
  if [[ "${dist_built}" -eq 1 ]]; then
    echo "[capi-smoke] ${UDID}"
    capi_require_no_simulator_app
    set +e
    capped_group 3600 "${ROOT_DIR}/scripts/run_ios_capi_smoke.sh" --dist "${CAPI_DIST}" --work "${OUT_DIR}/capi-smoke" \
      --udid "${UDID}" --device-build > "${OUT_DIR}/capi-smoke.log" 2>&1
    code=$?
    set -e
    capi_runner step-record --step smoke --exit-code "${code}" --timed-out "$([[ "${code}" -eq 142 ]] && echo 1 || echo 0)" \
      --log "${OUT_DIR}/capi-smoke.log" --results "${RESULTS}"
  else
    capi_runner step-record --step smoke --not-run "the distributable was not built" --results "${RESULTS}"
  fi

  capi_runner summary --results "${RESULTS}"
  exit 0
fi

# --- The device's checks of the C ABI (--capi-device; stage 2 working notes, 17.1 decision 4; part 1, 6 P1-20;
# part 2, 15.2). The same guards as the sample's device runs: --dry-run writes the approval list and stops
# before anything reaches the device or signs; --approved checks it and consumes its ID before the cleanup trap
# is set and the device is touched; device-gate checks the approved plan again before each call that reaches
# the device or signs. The device's result bundles, DerivedData and logs stay in DEVICE_TMP, which the trap
# removes; only the judgements go to results.jsonl.
if [[ "${CAPI_DEVICE}" -eq 1 ]]; then
  capi_runner() { python3 "${ROOT_DIR}/scripts/ios_capi_runner.py" "$@"; }
  capi_runner check-xcode --xcode "${XCODE}" --device
  capi_runner device-team --repo "${ROOT_DIR}" --check
  CAPI_VERSION="$(capi_runner version --common-h "${IOS_DIR}/IosLibraryCApi/include/NativeToolkitC/Common.h")"

  # The expected tests: IosLibraryCApiTests enumerated on the simulator (never the device), in this run's folder.
  status=0
  pgrep -x Simulator > /dev/null || status=$?
  if [[ "${status}" -ne 1 ]]; then
    echo "Error: Simulator.app is open, or pgrep failed (status ${status}); close it and run again (agent-rules/device-testing.md)" >&2; exit 2
  fi
  ENUM_INITIAL_STATE="$(runner capi-simulator-state --udid "${ENUM_UDID}" --simctl-devices "${OUT_DIR}/simctl-devices.json")"
  restore_enumeration_simulator() {
    if [[ "${ENUM_INITIAL_STATE}" == "Shutdown" ]]; then
      capped 120 xcrun simctl shutdown "${ENUM_UDID}" > /dev/null 2>&1 || true
    fi
  }
  echo "[capi-device] enumerate IosLibraryCApiTests on the simulator ${ENUM_UDID}"
  sim_xcodebuild 3600 build-for-testing -workspace "${WORKSPACE}" -scheme IosLibraryCApi \
    -destination "platform=iOS Simulator,id=${ENUM_UDID}" -derivedDataPath "${OUT_DIR}/dd-enumerate-build" -quiet \
    > "${OUT_DIR}/capi-enumerate-build.log" 2>&1 \
    || { restore_enumeration_simulator; echo "Error: the simulator build failed (${OUT_DIR}/capi-enumerate-build.log)" >&2; exit 1; }
  CAPI_XCTESTRUN="$(ls "${OUT_DIR}"/dd-enumerate-build/Build/Products/*iphonesimulator*.xctestrun)"
  [[ "$(echo "${CAPI_XCTESTRUN}" | wc -l | tr -d ' ')" == 1 ]] \
    || { restore_enumeration_simulator; echo "Error: expected one simulator .xctestrun" >&2; exit 1; }
  sim_xcodebuild 600 test-without-building -xctestrun "${CAPI_XCTESTRUN}" -destination "platform=iOS Simulator,id=${ENUM_UDID}" \
    -derivedDataPath "${OUT_DIR}/dd-enumerate" -resultBundlePath "${OUT_DIR}/capi-enumerate.xcresult" \
    -only-testing:IosLibraryCApiTests -enumerate-tests -test-enumeration-style flat -test-enumeration-format json \
    -test-enumeration-output-path "${OUT_DIR}/capi-enumeration.json" > "${OUT_DIR}/capi-enumerate.log" 2>&1 \
    || { restore_enumeration_simulator; echo "Error: the enumeration failed (${OUT_DIR}/capi-enumerate.log)" >&2; exit 1; }
  restore_enumeration_simulator

  plan_args=(--udid "${UDID}" --head "$(git -C "${ROOT_DIR}" rev-parse HEAD)" --xcode "${XCODE}" --version "${CAPI_VERSION}"
    --repo "${ROOT_DIR}" --plan "${PLAN}" --enumeration "${OUT_DIR}/capi-enumeration.json")
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    capi_runner device-plan "${plan_args[@]}" --dry-run --approval-out "${OUT_DIR}/approval.json"
    echo "[dry-run] stopped before anything reached the device or was signed"
    exit 0
  fi
  capi_runner device-plan "${plan_args[@]}"
  capi_runner device-approve --plan "${PLAN}" --approved "${APPROVED}" --repo "${ROOT_DIR}" \
    --head "$(git -C "${ROOT_DIR}" rev-parse HEAD)"
  APPROVAL_CONSUMED=1
  setup_device_tmp
  cp "${PLAN}" "${DEVICE_TMP}/plan.approved.json"
  chmod 0444 "${DEVICE_TMP}/plan.approved.json"
  PLAN="${DEVICE_TMP}/plan.approved.json"

  echo "[capi-device] library ${CAPI_VERSION}; results in ${RESULTS}"

  # 0. The device that --devicectl-id names must be the approved one (reads only; its details are not printed).
  capi_device_gate_or_stop
  set +e
  capi_device_devicectl 300 device info details --device "${DEVICECTL_ID}" --json-output "${DEVICE_TMP}/devicectl-info.json" \
    > "${DEVICE_TMP}/devicectl-info.log" 2>&1
  code=$?
  set -e
  if [[ "${code}" -ne 0 ]]; then
    echo "Error: devicectl device info details failed (status ${code}); nothing else reaches the device" >&2; exit 1
  fi
  capi_runner device-identity --plan "${PLAN}" --devicectl-json "${DEVICE_TMP}/devicectl-info.json" || exit 1

  # 1. IosLibraryCApiTests with ASan on the device.
  echo "[capi-device] IosLibraryCApiTests with ASan"
  dd="${DEVICE_TMP}/dd-capi-asan"
  bundle="${DEVICE_TMP}/capi-unit-asan.xcresult"
  log="${DEVICE_TMP}/capi-unit-asan.log"
  capi_device_gate_or_stop
  set +e
  capi_device_xcodebuild 3600 test -workspace "${WORKSPACE}" -scheme IosLibraryCApi -destination "platform=iOS,id=${UDID}" \
    -allowProvisioningUpdates -derivedDataPath "${dd}" -collect-test-diagnostics never -parallel-testing-enabled NO \
    -only-testing:IosLibraryCApiTests -resultBundlePath "${bundle}" -enableAddressSanitizer YES > "${log}" 2>&1
  code=$?
  set -e
  summary_json="${DEVICE_TMP}/capi-unit-asan-summary.json"
  action_log="${DEVICE_TMP}/capi-unit-asan-action.json"
  tests_json="${DEVICE_TMP}/capi-unit-asan-tests.json"
  if [[ -d "${bundle}" ]]; then
    xcrun xcresulttool get test-results tests --path "${bundle}" > "${tests_json}" || rm -f "${tests_json}"
    xcrun xcresulttool get test-results summary --path "${bundle}" > "${summary_json}" || rm -f "${summary_json}"
    xcrun xcresulttool get log --type action --path "${bundle}" > "${action_log}" || rm -f "${action_log}"
  fi
  otool_args=()
  for framework in IosLibraryCApi IosLibrary; do
    binary="${dd}/Build/Products/Debug-iphoneos/${framework}.framework/${framework}"
    listing="${DEVICE_TMP}/capi-unit-asan-otool-${framework}.txt"
    if [[ -f "${binary}" ]] && otool -L "${binary}" > "${listing}"; then
      otool_args+=(--otool "${framework}" "${listing}")
    fi
  done
  capi_runner device-unit-record --plan "${PLAN}" --tests-json "${tests_json}" --exit-code "${code}" --timed-out "$([[ "${code}" -eq 142 ]] && echo 1 || echo 0)" \
    --summary-json "${summary_json}" --log "test log" "${log}" --log "action log" "${action_log}" \
    ${otool_args[@]+"${otool_args[@]}"} --results "${RESULTS}"
  rm -rf "${bundle:?}"

  # 2. The distributable, unsigned, in this run's folder (nothing reaches the device).
  echo "[capi-device] build the distributable ${CAPI_VERSION}"
  CAPI_DIST="${OUT_DIR}/capi-dist"
  capi_device_env
  set +e
  capped_group 3600 "${CAPI_DEVICE_ENV[@]}" "${ROOT_DIR}/scripts/build_ios_library_xcframework.sh" -m IosLibrary -m IosLibraryCApi -v "${CAPI_VERSION}" \
    --output-dir "${CAPI_DIST}" --build-dir "${OUT_DIR}/capi-dist-build" --keep-project-versions \
    > "${OUT_DIR}/capi-dist-build.log" 2>&1
  code=$?
  set -e
  capi_runner device-step-record --step device-dist-build --exit-code "${code}" \
    --timed-out "$([[ "${code}" -eq 142 ]] && echo 1 || echo 0)" --log "${OUT_DIR}/capi-dist-build.log" --results "${RESULTS}"

  # 3. The smoke from the distributable alone, signed for the device with the team of the C ABI's project.
  SMOKE_APP="${DEVICE_TMP}/capi-smoke/dd-device/Build/Products/Release-iphoneos/IosLibraryCApiSmoke.app"
  smoke_built=0
  if [[ "${code}" -ne 0 ]]; then
    capi_runner device-step-record --step device-smoke-build --not-run "the distributable was not built" --results "${RESULTS}"
  else
    echo "[capi-device] build the smoke for the device (signed)"
    capi_device_env
    capi_device_gate_or_stop
    set +e
    capped_group 3600 "${CAPI_DEVICE_ENV[@]}" NTK_SMOKE_DEVELOPMENT_TEAM="$(capi_runner device-team --repo "${ROOT_DIR}")" "${ROOT_DIR}/scripts/run_ios_capi_smoke.sh" --dist "${CAPI_DIST}" --work "${DEVICE_TMP}/capi-smoke" --signed-device-build --plan "${PLAN}" --approved "${APPROVED}" > "${DEVICE_TMP}/capi-smoke-build.log" 2>&1
    code=$?
    set -e
    capi_runner device-step-record --step device-smoke-build --exit-code "${code}" \
      --timed-out "$([[ "${code}" -eq 142 ]] && echo 1 || echo 0)" --log "${DEVICE_TMP}/capi-smoke-build.log" --results "${RESULTS}"
    if [[ "$(capi_runner last-status --results "${RESULTS}")" == PASS && -d "${SMOKE_APP}" ]]; then
      smoke_built=1
    fi
  fi

  # 4-5. Install the smoke and launch it with its console attached; it prints SMOKE lines and ends itself.
  if [[ "${smoke_built}" -ne 1 ]]; then
    capi_runner device-step-record --step device-smoke-install --not-run "the smoke was not built" --results "${RESULTS}"
    capi_runner device-step-record --step device-smoke-run --not-run "the smoke was not built" --results "${RESULTS}"
  else
    echo "[capi-device] install the smoke"
    capi_device_gate_or_stop
    set +e
    capi_device_devicectl 300 device install app --device "${DEVICECTL_ID}" "${SMOKE_APP}" > "${DEVICE_TMP}/smoke-install.log" 2>&1
    code=$?
    set -e
    capi_runner device-step-record --step device-smoke-install --exit-code "${code}" \
      --timed-out "$([[ "${code}" -eq 142 ]] && echo 1 || echo 0)" --log "${DEVICE_TMP}/smoke-install.log" --results "${RESULTS}"
    if [[ "${code}" -ne 0 ]]; then
      capi_runner device-step-record --step device-smoke-run --not-run "the smoke was not installed" --results "${RESULTS}"
    else
      echo "[capi-device] launch the smoke (do not touch the screen)"
      capi_device_gate_or_stop
      set +e
      capi_device_devicectl 180 device process launch --device "${DEVICECTL_ID}" --console --terminate-existing \
        com.jonghyunkim.nativetoolkit.IosLibraryCApiSmoke > "${DEVICE_TMP}/smoke-run.log" 2>&1
      code=$?
      set -e
      capi_runner device-step-record --step device-smoke-run --exit-code "${code}" \
        --timed-out "$([[ "${code}" -eq 142 ]] && echo 1 || echo 0)" --log "${DEVICE_TMP}/smoke-run.log" --results "${RESULTS}"
    fi
  fi

  echo "[capi-device] left on the device (not removed): com.jonghyunkim.nativetoolkit.IosLibraryCApiTestHost, com.jonghyunkim.nativetoolkit.IosLibraryCApiSmoke"
  capi_runner device-summary --results "${RESULTS}"
  exit 0
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
