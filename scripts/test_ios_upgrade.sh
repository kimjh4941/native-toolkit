#!/usr/bin/env bash
# The upgrade test from the 1.13.0 sample (IosLibrary 1.3.0) to 2.0.0, on a simulator only
# (artifact/topics/ios-c-abi/README.md chapter 7 and the DoD; the design is
# artifact/topics/ios-c-abi/designs/2026-11-21-ios-c-abi-upgrade-test-design.md, chapter 6).
#
# Usage:
#   ./scripts/test_ios_upgrade.sh --udid <simulator UDID> [--group A|B|C]...
#
# For each group (all three by default) it deletes the sample, installs the 1.13.0 sample built
# from the tag 1.13.0 in a temporary git worktree, grants it the location, puts the location in
# Osaka, runs the 1.x half (UpgradeUITests/testU?1_*) through a copy of the xctestrun whose target
# app and framework search paths are the 1.x build's, then runs the 2.0.0 half (testU?2_*) through
# the normal xctestrun, which installs 2.0.0 over the 1.x sample. Groups B and C wait for the 2.0.0
# half's signal file and then move the location to Tokyo Station, which fires the 1.x notification.
# A half passes only with exactly one Passed result for it, a zero exit code within 10 minutes, a
# readable result bundle from this simulator (ios_ui_runner.py upgrade-judge), and the expected
# IosLibrary in the installed app (1.x after the 1.x half, 2.0.0 after the 2.0.0 half).
#
# It never runs on a device. It changes the simulator's location, the sample's location permission
# and the sample itself, and puts them back at the end (also when it stops early). Results and
# logs: ios/IosLibraryExample/build/test_ios_upgrade/<time>/.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
TESTS_DIR="${ROOT_DIR}/ios/IosLibraryExample/IosLibraryExampleUITests"
PBXPROJ="${ROOT_DIR}/ios/IosLibraryExample/IosLibraryExample.xcodeproj/project.pbxproj"
WORKSPACE="${ROOT_DIR}/ios/IosWorkspace.xcworkspace"
BUNDLE_ID="com.jonghyunkim.ios.nativetoolkit.example"
LEGACY_TAG="1.13.0"
LEGACY_FRAMEWORK_ID="ios.library.IosLibrary"
LEGACY_FRAMEWORK_VERSION="1.3.0"
CURRENT_FRAMEWORK_ID="com.jonghyunkim.nativetoolkit.IosLibrary"
OSAKA="34.7025,135.4959"
TOKYO_STATION="35.6812,139.7671"
HALF_SECONDS=600
SIGNAL_SECONDS=180

# Nothing from outside may reach the test runner or the device gate (test_ios.sh does the same).
unset TEST_RUNNER_NTK_DEVICE_ALLOW NTK_DEVICE_ALLOW \
  NTK_UPGRADE_STEP TEST_RUNNER_NTK_UPGRADE_STEP SIMCTL_CHILD_NTK_UPGRADE_STEP \
  NTK_UPGRADE_SIGNAL TEST_RUNNER_NTK_UPGRADE_SIGNAL SIMCTL_CHILD_NTK_UPGRADE_SIGNAL

usage() {
  sed -n '6,8p' "$0" | sed 's/^# \{0,1\}//'
}

UDID=""
SELECTED_GROUPS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; UDID="$2"; shift 2 ;;
    --group) [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      case "$2" in A|B|C) SELECTED_GROUPS+=("$2") ;; *) echo "Error: --group takes A, B or C" >&2; exit 2 ;; esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown argument $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "${UDID}" ]] || { echo "Error: --udid is required" >&2; usage >&2; exit 2; }
[[ ${#SELECTED_GROUPS[@]} -gt 0 ]] || SELECTED_GROUPS=(A B C)

runner() { python3 -I "${ROOT_DIR}/scripts/ios_ui_runner.py" "$@"; }
# Runs a command in its own process group with a time limit (the same program as test_ios.sh's
# capped_group): when the time is up, or on INT, TERM or HUP, the whole group (xcodebuild and what it
# started) is killed and reaped, and the status is 142 (time) or 128 + the signal. Started directly,
# also in the background, so that `$!` is this perl process and a TERM to it stops the whole group.
CAPPED_GROUP='my $seconds = shift; die "time limit: $seconds\n" unless $seconds =~ /^[1-9][0-9]*$/;
  my $pid = fork; die "fork: $!\n" unless defined $pid;
  if ($pid == 0) { setpgrp(0, 0); exec @ARGV or exit 127; }
  setpgrp($pid, $pid);
  $SIG{ALRM} = sub { kill "KILL", -$pid; waitpid($pid, 0); exit 142; };
  my %number = (HUP => 1, INT => 2, TERM => 15);
  for my $name (keys %number) {
    $SIG{$name} = sub { kill "KILL", -$pid; waitpid($pid, 0); exit 128 + $number{$name}; };
  }
  alarm $seconds; waitpid($pid, 0); alarm 0;
  exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);'
capped() {  # <seconds> <command...>
  perl -e "${CAPPED_GROUP}" "$@" < /dev/null
}

# --- 1. The simulator and Simulator.app ------------------------------------------------------------
simulator_state() {
  xcrun simctl list -j devices | python3 -I -c '
import json, sys
udid = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["udid"] == udid:
            print(d["state"]); sys.exit(0)
sys.exit(1)' "${UDID}"
}
INITIAL_STATE="$(simulator_state)" || { echo "Error: ${UDID} is not a simulator of this Mac" >&2; exit 2; }
status=0
pgrep -x Simulator > /dev/null || status=$?
if [[ "${status}" -eq 0 ]]; then
  echo "Error: Simulator.app is open; close it and run again (agent-rules/device-testing.md)" >&2; exit 2
elif [[ "${status}" -ne 1 ]]; then
  echo "Error: pgrep failed (status ${status}); cannot tell whether Simulator.app is open" >&2; exit 2
fi

# --- 2. The sources, the trusted part and the declarations --------------------------------------------
runner upgrade-check --tests-dir "${TESTS_DIR}" --pbxproj "${PBXPROJ}" || exit 1

OUT_DIR="${ROOT_DIR}/ios/IosLibraryExample/build/test_ios_upgrade/$(date '+%Y%m%d-%H%M%S')"
mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd -P "${OUT_DIR}" && pwd -P)"
LEGACY_TREE="${OUT_DIR}/legacy"
SIGNAL="${OUT_DIR}/signal"
echo "[out] ${OUT_DIR}"

# --- 3. The clean-up, also when the run stops early ------------------------------------------------
BACKGROUND_PID=""
cleanup() {
  if [[ -n "${BACKGROUND_PID}" ]] && kill -0 "${BACKGROUND_PID}" 2>/dev/null; then
    # TERM to the perl wrapper: it kills the whole xcodebuild group and reaps it before it exits.
    kill -TERM "${BACKGROUND_PID}" 2>/dev/null; wait "${BACKGROUND_PID}" 2>/dev/null
  fi
  BACKGROUND_PID=""
  if [[ "$(simulator_state 2>/dev/null)" == "Booted" ]]; then
    xcrun simctl location "${UDID}" clear >/dev/null 2>&1
    xcrun simctl privacy "${UDID}" reset location "${BUNDLE_ID}" >/dev/null 2>&1
    xcrun simctl uninstall "${UDID}" "${BUNDLE_ID}" >/dev/null 2>&1
  fi
  if [[ -d "${LEGACY_TREE}" ]]; then
    git -C "${ROOT_DIR}" worktree remove --force "${LEGACY_TREE}" >/dev/null 2>&1
  fi
  git -C "${ROOT_DIR}" worktree prune >/dev/null 2>&1
  if [[ "${INITIAL_STATE}" == "Shutdown" ]]; then
    xcrun simctl shutdown "${UDID}" >/dev/null 2>&1
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# --- 4. The 1.x sample, from the tag ------------------------------------------------------------------
echo "[legacy] worktree ${LEGACY_TAG}"
git -C "${ROOT_DIR}" worktree add --detach "${LEGACY_TREE}" "${LEGACY_TAG}" > "${OUT_DIR}/worktree.log" 2>&1 \
  || { echo "Error: git worktree add failed (${OUT_DIR}/worktree.log)" >&2; exit 1; }
echo "[legacy] build"
(cd "${LEGACY_TREE}/ios" && capped 1800 xcodebuild build -workspace IosWorkspace.xcworkspace -scheme IosLibraryExample \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "${OUT_DIR}/dd-legacy" -quiet < /dev/null) \
  > "${OUT_DIR}/build-legacy.log" 2>&1 || { echo "Error: the 1.x build failed (${OUT_DIR}/build-legacy.log)" >&2; exit 1; }
LEGACY_PRODUCTS="${OUT_DIR}/dd-legacy/Build/Products/Debug-iphonesimulator"
LEGACY_APP="${LEGACY_PRODUCTS}/IosLibraryExample.app"
[[ -d "${LEGACY_APP}" ]] || { echo "Error: no 1.x app at ${LEGACY_APP}" >&2; exit 1; }

# --- 5. The current build and the 1.x xctestrun ----------------------------------------------------
echo "[current] build-for-testing"
capped 1800 xcodebuild build-for-testing -workspace "${WORKSPACE}" -scheme IosLibraryExample \
  -destination "platform=iOS Simulator,id=${UDID}" -derivedDataPath "${OUT_DIR}/dd-build" -quiet < /dev/null \
  > "${OUT_DIR}/build-current.log" 2>&1 || { echo "Error: the build failed (${OUT_DIR}/build-current.log)" >&2; exit 1; }
XCTESTRUNS=("${OUT_DIR}"/dd-build/Build/Products/*iphonesimulator*.xctestrun)
[[ ${#XCTESTRUNS[@]} -eq 1 && -f "${XCTESTRUNS[0]}" ]] || { echo "Error: expected one simulator xctestrun" >&2; exit 1; }
XCTESTRUN="${XCTESTRUNS[0]}"
LEGACY_XCTESTRUN="$(dirname "${XCTESTRUN}")/upgrade-legacy.xctestrun"
runner upgrade-xctestrun --source "${XCTESTRUN}" --legacy-products "${LEGACY_PRODUCTS}" --out "${LEGACY_XCTESTRUN}" || exit 1
# The IosLibrary version this run built: the 2.0.0 half must leave exactly it installed (U-4 (2)).
CURRENT_FRAMEWORK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$(dirname "${XCTESTRUN}")/Debug-iphonesimulator/IosLibrary.framework/Info.plist" 2>/dev/null)"
[[ -n "${CURRENT_FRAMEWORK_VERSION}" ]] || { echo "Error: cannot read the version of the IosLibrary this run built" >&2; exit 1; }

# --- 6. Boot (xcodebuild then leaves the simulator booted) --------------------------------------
xcrun simctl boot "${UDID}" >/dev/null 2>&1
xcrun simctl bootstatus "${UDID}" -b > /dev/null || { echo "Error: ${UDID} did not boot" >&2; exit 1; }

# --- 7. The groups ----------------------------------------------------------------------------
framework_check() {  # <half> <identifier> [version]: the IosLibrary inside the installed sample
  local container plist id version
  container="$(xcrun simctl get_app_container "${UDID}" "${BUNDLE_ID}" 2>/dev/null)" \
    || { echo "  FAIL $1: the sample is not installed"; return 1; }
  plist="${container}/Frameworks/IosLibrary.framework/Info.plist"
  id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${plist}" 2>/dev/null)"
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${plist}" 2>/dev/null)"
  if [[ "${id}" != "$2" || ( -n "${3:-}" && "${version}" != "$3" ) ]]; then
    echo "  FAIL $1: the installed IosLibrary is ${id} ${version}, not $2 ${3:-}"; return 1
  fi
  echo "  [version] $1: ${id} ${version}"
}

judge() {  # <step> <bundle> <exit code>
  local step="$1" bundle="$2" code="$3" timed_out=0 tests_json="${OUT_DIR}/$1-tests.json" summary_json="${OUT_DIR}/$1-summary.json"
  [[ "${code}" -eq 142 ]] && timed_out=1
  rm -f "${tests_json}" "${summary_json}"
  if [[ -d "${bundle}" ]]; then
    xcrun xcresulttool get test-results tests --path "${bundle}" > "${tests_json}" 2>/dev/null || rm -f "${tests_json}"
    xcrun xcresulttool get test-results summary --path "${bundle}" > "${summary_json}" 2>/dev/null || rm -f "${summary_json}"
  fi
  runner upgrade-judge --step "${step}" --tests-json "${tests_json}" --summary-json "${summary_json}" \
    --exit-code "${code}" --timed-out "${timed_out}" --udid "${UDID}"
}

only_testing() {  # <step>: the one -only-testing argument of the step, never empty
  local argument
  argument="$(python3 -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import ios_ui_runner as r
print(f"-only-testing:{r.UI_TARGET}/{r.upgrade_step_key(sys.argv[2])}")' "${ROOT_DIR}/scripts" "$1")" || return 1
  [[ "${argument}" == -only-testing:IosLibraryExampleUITests/UpgradeUITests/test* ]] || return 1
  printf '%s' "${argument}"
}

run_group() {  # <group> <first step> <second step> <fires: 0|1>
  local group="$1" first="$2" second="$3" fires="$4" code waited=0 first_only second_only
  first_only="$(only_testing "${first}")" || { echo "  FAIL ${group}: no -only-testing for ${first}"; return 1; }
  second_only="$(only_testing "${second}")" || { echo "  FAIL ${group}: no -only-testing for ${second}"; return 1; }
  echo "[group ${group}] ${first} -> ${second}"
  xcrun simctl uninstall "${UDID}" "${BUNDLE_ID}" >/dev/null 2>&1
  xcrun simctl install "${UDID}" "${LEGACY_APP}" || { echo "  FAIL ${group}: the 1.x sample did not install"; return 1; }
  xcrun simctl privacy "${UDID}" grant location "${BUNDLE_ID}" || { echo "  FAIL ${group}: grant location"; return 1; }
  xcrun simctl location "${UDID}" set "${OSAKA}" || { echo "  FAIL ${group}: set the location"; return 1; }
  rm -f "${SIGNAL}"

  capped "${HALF_SECONDS}" env TEST_RUNNER_NTK_UPGRADE_STEP="${first}" xcodebuild test-without-building \
    -xctestrun "${LEGACY_XCTESTRUN}" -destination "platform=iOS Simulator,id=${UDID}" \
    -derivedDataPath "${OUT_DIR}/dd-test" -parallel-testing-enabled NO -resultBundlePath "${OUT_DIR}/${first}.xcresult" \
    "${first_only}" < /dev/null > "${OUT_DIR}/${first}.log" 2>&1
  code=$?
  judge "${first}" "${OUT_DIR}/${first}.xcresult" "${code}" || { echo "  FAIL ${group}: the 1.x half failed; the 2.0.0 half is not run"; return 1; }
  framework_check "${first}" "${LEGACY_FRAMEWORK_ID}" "${LEGACY_FRAMEWORK_VERSION}" || return 1

  perl -e "${CAPPED_GROUP}" "${HALF_SECONDS}" env TEST_RUNNER_NTK_UPGRADE_STEP="${second}" TEST_RUNNER_NTK_UPGRADE_SIGNAL="${SIGNAL}" \
    xcodebuild test-without-building -xctestrun "${XCTESTRUN}" -destination "platform=iOS Simulator,id=${UDID}" \
    -derivedDataPath "${OUT_DIR}/dd-test" -parallel-testing-enabled NO -resultBundlePath "${OUT_DIR}/${second}.xcresult" \
    "${second_only}" < /dev/null > "${OUT_DIR}/${second}.log" 2>&1 &
  BACKGROUND_PID=$!  # the perl wrapper itself (not a subshell)
  if [[ "${fires}" -eq 1 ]]; then
    while [[ "$(cat "${SIGNAL}" 2>/dev/null)" != "${second}" ]]; do
      if ! kill -0 "${BACKGROUND_PID}" 2>/dev/null; then
        echo "  FAIL ${group}: the 2.0.0 half ended before its signal"; break
      fi
      if [[ "${waited}" -ge "${SIGNAL_SECONDS}" ]]; then
        echo "  FAIL ${group}: no signal from the 2.0.0 half in ${SIGNAL_SECONDS} s; stopping it"
        kill -TERM "${BACKGROUND_PID}" 2>/dev/null; break
      fi
      sleep 1; waited=$((waited + 1))
    done
    if [[ "$(cat "${SIGNAL}" 2>/dev/null)" == "${second}" ]]; then
      xcrun simctl location "${UDID}" set "${TOKYO_STATION}" && echo "  [location] Tokyo Station after ${waited} s"
    fi
  fi
  wait "${BACKGROUND_PID}"; code=$?
  BACKGROUND_PID=""
  judge "${second}" "${OUT_DIR}/${second}.xcresult" "${code}" || return 1
  if [[ "${fires}" -eq 1 && "$(cat "${SIGNAL}" 2>/dev/null)" != "${second}" ]]; then
    echo "  FAIL ${group}: the signal file does not name ${second}"; return 1
  fi
  framework_check "${second}" "${CURRENT_FRAMEWORK_ID}" "${CURRENT_FRAMEWORK_VERSION}" || return 1
  xcrun simctl location "${UDID}" clear >/dev/null 2>&1
}

FAILED=()
for group in "${SELECTED_GROUPS[@]}"; do
  case "${group}" in
    A) run_group A UA1 UA2 0 || FAILED+=(A) ;;
    B) run_group B UB1 UB2 1 || FAILED+=(B) ;;
    C) run_group C UC1 UC2 1 || FAILED+=(C) ;;
  esac
done

# --- 8. The result ------------------------------------------------------------------------------
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "[summary] the upgrade test passed: groups ${SELECTED_GROUPS[*]}"
  exit 0
fi
echo "[summary] the upgrade test FAILED: groups ${FAILED[*]} (of ${SELECTED_GROUPS[*]})"
exit 1
