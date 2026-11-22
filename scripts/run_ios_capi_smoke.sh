#!/usr/bin/env bash
set -euo pipefail

# Build and run the smoke of the iOS C ABI (ios/IosLibraryCApiSmoke; C ABI design part 2, 12.4;
# README 7, D-16) against a build of the distributable, with the Xcode that DEVELOPER_DIR names.
#
# Usage:
#   DEVELOPER_DIR=<Xcode>/Contents/Developer ./scripts/run_ios_capi_smoke.sh --dist <folder> --work <new folder>
#       [--udid <simulator>] [--device-build] [--archs <archs>]
#   NTK_SMOKE_DEVELOPMENT_TEAM=<team> ... --dist <folder> --work <new folder> --signed-device-build
#       --plan <approved plan> --approved <approval list>
#
#   --dist          the folder with ios-native-toolkit-<v>.xcframework and ios-native-toolkit-capi-<v>.xcframework
#                   (scripts/build_ios_library_xcframework.sh --output-dir, or dist/<release>/ios)
#   --work          a folder that does not exist yet: the smoke's sources and the two xcframeworks are
#                   copied there and built there, so the build reaches nothing else of the repository
#   --udid          a simulator to install and run the app on (Simulator.app must be closed)
#   --device-build  also build for generic/platform=iOS without signing (CODE_SIGNING_ALLOWED=NO). It is
#                   never installed: a device run needs the user's approval (agent-rules/device-testing.md)
#   --archs         the simulator architectures to build (default: the Release default, arm64 and x86_64)
#   --signed-device-build
#                   build for generic/platform=iOS signed (Automatic, NTK_SMOKE_DEVELOPMENT_TEAM,
#                   -allowProvisioningUpdates) and never install it: only scripts/test_ios.sh --capi-device
#                   installs it, after the user's approval. Takes neither --udid nor --device-build; the
#                   team is never printed or written by this script (its value comes from the environment).
#                   It signs only when --plan and --approved pass the gate of ios_capi_runner.py device-gate (an
#                   approval consumed in the ledger for this plan, the runner and the tree as approved), and
#                   builds without XCODE_XCCONFIG_FILE, TOOLCHAINS and the TEST_RUNNER_ variables
#
# What it checks: the app builds from the two xcframeworks alone; it embeds exactly IosLibrary.framework
# and IosLibraryCApi.framework and no Swift library, and its own binary needs no Swift library and
# imports nothing of IosLibrary; on the simulator, every step prints SMOKE PASS and the app ends with
# "SMOKE RESULT PASS" (ntk_notification_install, a named pasteboard written and read, a dialog shown and
# cancelled to its completion). Exit status 1 when anything failed.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
SMOKE_DIR="${ROOT_DIR}/ios/IosLibraryCApiSmoke"
APP="IosLibraryCApiSmoke"
BUNDLE_ID="com.jonghyunkim.nativetoolkit.IosLibraryCApiSmoke"
# How long the launch may take before it counts as hung; NTK_SMOKE_LAUNCH_SECONDS shortens it (to
# check that a hang fails).
LAUNCH_SECONDS="${NTK_SMOKE_LAUNCH_SECONDS:-120}"

DIST=""
WORK=""
UDID=""
DEVICE_BUILD=0
SIGNED_DEVICE_BUILD=0
ARCHS=""
PLAN=""
APPROVED=""

usage() {
  sed -n '4,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dist) DIST="${2:?--dist needs a value}"; shift 2 ;;
    --work) WORK="${2:?--work needs a value}"; shift 2 ;;
    --udid) UDID="${2:?--udid needs a value}"; shift 2 ;;
    --device-build) DEVICE_BUILD=1; shift ;;
    --signed-device-build) SIGNED_DEVICE_BUILD=1; shift ;;
    --plan) PLAN="${2:?--plan needs a value}"; shift 2 ;;
    --approved) APPROVED="${2:?--approved needs a value}"; shift 2 ;;
    --archs) ARCHS="${2:?--archs needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
if [[ -z "${DIST}" || -z "${WORK}" ]]; then
  echo "Error: --dist and --work are required." >&2
  usage
  exit 2
fi
if [[ "${SIGNED_DEVICE_BUILD}" == "1" ]]; then
  if [[ "${DEVICE_BUILD}" == "1" || -n "${UDID}" ]]; then
    echo "Error: --signed-device-build takes neither --device-build nor --udid." >&2
    exit 2
  fi
  if [[ ! "${NTK_SMOKE_DEVELOPMENT_TEAM:-}" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Error: --signed-device-build needs NTK_SMOKE_DEVELOPMENT_TEAM (ten letters and digits)." >&2
    exit 2
  fi
  # Signing (and -allowProvisioningUpdates) only for an approved --capi-device run: the same gate as every step
  # of test_ios.sh --capi-device that reaches the device or signs.
  if [[ -z "${PLAN}" || -z "${APPROVED}" ]] \
      || ! python3 "${ROOT_DIR}/scripts/ios_capi_runner.py" device-gate --plan "${PLAN}" --approved "${APPROVED}" \
           --repo "${ROOT_DIR}" > /dev/null; then
    echo "Error: --signed-device-build signs only with --plan and --approved of an approved, consumed --capi-device run (scripts/test_ios.sh --capi-device)." >&2
    exit 2
  fi
elif [[ -n "${PLAN}" || -n "${APPROVED}" ]]; then
  echo "Error: --plan and --approved are for --signed-device-build." >&2
  exit 2
fi
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  echo "Error: set DEVELOPER_DIR to the Xcode to build with (this script never switches Xcode)." >&2
  exit 2
fi
if [[ -e "${WORK}" ]]; then
  echo "Error: ${WORK} exists; give a new folder." >&2
  exit 2
fi

shopt -s nullglob
capi=("${DIST}"/ios-native-toolkit-capi-*.xcframework)
shopt -u nullglob
if [[ ${#capi[@]} -ne 1 ]]; then
  echo "Error: ${DIST} needs exactly one ios-native-toolkit-capi-<version>.xcframework." >&2
  exit 2
fi
VERSION="$(basename "${capi[0]}" .xcframework)"
VERSION="${VERSION#ios-native-toolkit-capi-}"
LIBRARY_XCFRAMEWORK="${DIST}/ios-native-toolkit-${VERSION}.xcframework"
if [[ ! -d "${LIBRARY_XCFRAMEWORK}" ]]; then
  echo "Error: ${LIBRARY_XCFRAMEWORK} is missing." >&2
  exit 2
fi

FAILED=0
SUMMARY=()
record() {
  SUMMARY+=("$1 $2${3:+: $3}")
  if [[ "$1" == "FAIL" ]]; then
    FAILED=1
  fi
}

mkdir -p "${WORK}/logs"
PROJECT_COPY="${WORK}/${APP}"
# The smoke's sources only (no staged Frameworks/), then the two xcframeworks under the names the
# project references.
mkdir -p "${PROJECT_COPY}/Frameworks"
ditto "${SMOKE_DIR}/${APP}" "${PROJECT_COPY}/${APP}"
ditto "${SMOKE_DIR}/${APP}.xcodeproj" "${PROJECT_COPY}/${APP}.xcodeproj"
ditto "${LIBRARY_XCFRAMEWORK}" "${PROJECT_COPY}/Frameworks/IosLibrary.xcframework"
ditto "${capi[0]}" "${PROJECT_COPY}/Frameworks/IosLibraryCApi.xcframework"
XCODE_VERSION="$(xcodebuild -version | tr '\n' ' ')"
echo "[smoke] ${XCODE_VERSION}; library ${VERSION}; work ${WORK}"

# Checks a built app: what it embeds and what its own binary needs.
check_app() {
  local label=$1 app=$2
  local embedded own_dependencies own_imports imported
  if [[ ! -d "${app}" ]]; then
    record FAIL "${label} app" "not built"
    return
  fi
  embedded="$(cd "${app}/Frameworks" 2>/dev/null && ls | sort | tr '\n' ' ')"
  if [[ "${embedded}" == "IosLibrary.framework IosLibraryCApi.framework " ]]; then
    record PASS "${label} embeds" "${embedded}"
  else
    record FAIL "${label} embeds" "${embedded:-nothing}"
  fi
  # Each tool's status is read before its output: a failed tool must not read as "nothing found".
  if ! own_dependencies="$(otool -L "${app}/${APP}")"; then
    record FAIL "${label} needs no Swift library" "otool -L failed"
  elif grep -q 'libswift' <<<"$(sed 1d <<<"${own_dependencies}")"; then
    record FAIL "${label} needs no Swift library" "$(grep libswift <<<"${own_dependencies}" | tr -s ' \t' ' ')"
  elif ! grep -q '@rpath/IosLibraryCApi.framework/IosLibraryCApi' <<<"${own_dependencies}"; then
    record FAIL "${label} needs IosLibraryCApi" "it does not"
  else
    record PASS "${label} needs no Swift library"
  fi
  # The app calls C only: nothing it imports is a Swift symbol of IosLibrary.
  if ! imported="$(nm -u -arch all "${app}/${APP}")" || [[ -z "${imported}" ]]; then
    record FAIL "${label} imports nothing of IosLibrary" "nm -u failed or listed nothing"
    return
  fi
  own_imports="$(grep -c '\$s10IosLibrary' <<<"${imported}" || true)"
  if [[ "${own_imports}" == "0" ]]; then
    record PASS "${label} imports nothing of IosLibrary"
  else
    record FAIL "${label} imports nothing of IosLibrary" "${own_imports} Swift symbols"
  fi
}

simulator_args=()
if [[ -n "${ARCHS}" ]]; then
  simulator_args+=("ARCHS=${ARCHS}" "ONLY_ACTIVE_ARCH=NO")
fi
echo "[smoke] building for the simulator"
if xcodebuild build -project "${PROJECT_COPY}/${APP}.xcodeproj" -scheme "${APP}" -configuration Release \
    -destination "generic/platform=iOS Simulator" -derivedDataPath "${WORK}/dd-simulator" \
    ${simulator_args[@]+"${simulator_args[@]}"} > "${WORK}/logs/build-simulator.log" 2>&1; then
  SIMULATOR_APP="${WORK}/dd-simulator/Build/Products/Release-iphonesimulator/${APP}.app"
  if archs="$(lipo -archs "${SIMULATOR_APP}/${APP}")"; then
    record PASS "simulator build" "${archs}"
  else
    record FAIL "simulator build" "lipo -archs failed"
  fi
  check_app simulator "${SIMULATOR_APP}"
else
  SIMULATOR_APP=""
  record FAIL "simulator build" "see ${WORK}/logs/build-simulator.log"
  grep -E 'error:' "${WORK}/logs/build-simulator.log" | head -10 >&2 || true
fi

if [[ "${DEVICE_BUILD}" == "1" ]]; then
  echo "[smoke] building for the device (not signed, not installed)"
  if xcodebuild build -project "${PROJECT_COPY}/${APP}.xcodeproj" -scheme "${APP}" -configuration Release \
      -destination "generic/platform=iOS" -derivedDataPath "${WORK}/dd-device" CODE_SIGNING_ALLOWED=NO \
      > "${WORK}/logs/build-device.log" 2>&1; then
    if archs="$(lipo -archs "${WORK}/dd-device/Build/Products/Release-iphoneos/${APP}.app/${APP}")"; then
      record PASS "device build" "${archs}"
    else
      record FAIL "device build" "lipo -archs failed"
    fi
    check_app device "${WORK}/dd-device/Build/Products/Release-iphoneos/${APP}.app"
  else
    record FAIL "device build" "see ${WORK}/logs/build-device.log"
    grep -E 'error:' "${WORK}/logs/build-device.log" | head -10 >&2 || true
  fi
fi

if [[ "${SIGNED_DEVICE_BUILD}" == "1" ]]; then
  echo "[smoke] building for the device, signed (not installed)"
  clean_env=(env -u XCODE_XCCONFIG_FILE -u TOOLCHAINS)
  for name in $(compgen -e); do
    [[ "${name}" == TEST_RUNNER_* ]] && clean_env+=(-u "${name}")
  done
  if "${clean_env[@]}" xcodebuild build -project "${PROJECT_COPY}/${APP}.xcodeproj" -scheme "${APP}" -configuration Release \
      -destination "generic/platform=iOS" -derivedDataPath "${WORK}/dd-device" -allowProvisioningUpdates \
      CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=${NTK_SMOKE_DEVELOPMENT_TEAM}" "CODE_SIGN_IDENTITY=Apple Development" \
      > "${WORK}/logs/build-device-signed.log" 2>&1; then
    if archs="$(lipo -archs "${WORK}/dd-device/Build/Products/Release-iphoneos/${APP}.app/${APP}")"; then
      record PASS "device build (signed)" "${archs}"
    else
      record FAIL "device build (signed)" "lipo -archs failed"
    fi
    check_app device "${WORK}/dd-device/Build/Products/Release-iphoneos/${APP}.app"
  else
    # The log names the signing identity; it stays in WORK and is not printed.
    record FAIL "device build (signed)" "see ${WORK}/logs/build-device-signed.log"
  fi
fi

# Installs and runs the app on UDID. Every failure is recorded and ends the run, so that the summary
# is still printed.
run_on_simulator() {
  local devices booted_here=0 log output status=0
  # Read whole: grep -q would end the pipe early, and pipefail would take simctl's SIGPIPE as a failure.
  if ! devices="$(xcrun simctl list devices)"; then
    record FAIL "simulator run" "simctl list failed"
    return
  fi
  # Simulator.app syncs the simulator's pasteboard with the Mac's (agent-rules/device-testing.md).
  # The smoke writes a named pasteboard only, but it still does not run while Simulator.app is open,
  # and it never opens or closes Simulator.app.
  if pgrep -x Simulator >/dev/null; then
    record FAIL "simulator run" "Simulator.app is open; close it and run again"
    return
  fi
  if ! grep -q "(${UDID})" <<<"${devices}"; then
    record FAIL "simulator run" "${UDID} is not a simulator"
    return
  fi
  if ! grep "(${UDID})" <<<"${devices}" | grep -q Booted; then
    if ! xcrun simctl boot "${UDID}"; then
      record FAIL "simulator run" "simctl boot ${UDID} failed"
      return
    fi
    booted_here=1
  fi
  log="${WORK}/logs/run-${UDID}.log"
  if ! xcrun simctl bootstatus "${UDID}" -b > /dev/null; then
    record FAIL "simulator run" "simctl bootstatus ${UDID} failed"
  else
    xcrun simctl uninstall "${UDID}" "${BUNDLE_ID}" > /dev/null 2>&1 || true
    if ! xcrun simctl install "${UDID}" "${SIMULATOR_APP}"; then
      record FAIL "simulator run" "simctl install failed"
    else
      echo "[smoke] running on ${UDID}"
      # The app ends itself (60 seconds at most); a launch that is still running after LAUNCH_SECONDS is
      # killed and ends with status 142. simctl handles SIGALRM itself and exits 0, so the alarm is the
      # parent's: it waits for simctl and, when the time is up, kills its whole process group (simctl and
      # anything it started). stdin is /dev/null, as the group is not the terminal's foreground group.
      perl -e 'my $seconds = shift; die "launch seconds: $seconds\n" unless $seconds =~ /^[1-9][0-9]*$/;
               my $pid = fork; die "fork: $!" unless defined $pid;
               if ($pid == 0) { setpgrp(0, 0); exec @ARGV or exit 127; }
               setpgrp($pid, $pid);
               $SIG{ALRM} = sub { kill "KILL", -$pid; waitpid($pid, 0); exit 142; };
               alarm $seconds; waitpid($pid, 0); alarm 0;
               exit(($? & 127) ? 128 + ($? & 127) : $? >> 8);' \
        "${LAUNCH_SECONDS}" xcrun simctl launch --console-pty --terminate-running-process \
        "${UDID}" "${BUNDLE_ID}" < /dev/null > "${log}" 2>&1 || status=$?
      if [[ "${status}" -ne 0 ]]; then
        # The app is the simulator's, not a child of simctl: end it too.
        xcrun simctl terminate "${UDID}" "${BUNDLE_ID}" > /dev/null 2>&1 || true
      fi
      output="$(tr -d '\r' < "${log}")"
      grep -E '^SMOKE ' <<<"${output}" || true
      if [[ "${status}" -ne 0 ]]; then
        # PASS lines before a hang or a crash do not make a pass.
        record FAIL "simulator run" "${UDID}: the launch ended with status ${status}$([[ "${status}" -eq 142 ]] && echo " (the ${LAUNCH_SECONDS}-second alarm)"); see ${log}"
      elif grep -q '^SMOKE RESULT PASS failures=0$' <<<"${output}" && ! grep -q '^SMOKE FAIL' <<<"${output}"; then
        record PASS "simulator run" "${UDID}: $(grep -c '^SMOKE PASS' <<<"${output}") steps"
      else
        record FAIL "simulator run" "${UDID}: see ${log}"
      fi
      xcrun simctl uninstall "${UDID}" "${BUNDLE_ID}" > /dev/null 2>&1 || true
    fi
  fi
  if [[ "${booted_here}" == "1" ]]; then
    xcrun simctl shutdown "${UDID}" || true
  fi
}

if [[ -n "${UDID}" && -n "${SIMULATOR_APP}" ]]; then
  run_on_simulator
fi

echo "== iOS C ABI smoke (${XCODE_VERSION}, library ${VERSION})"
for line in "${SUMMARY[@]}"; do
  echo "  ${line}"
done
exit "${FAILED}"
