#!/usr/bin/env bash
set -euo pipefail

# Run the smoke of the Android C ABI (android/android_library_capi_smoke; C ABI design part 1,
# chapter 6; part 2, 12.4) on one device, against a Maven repository the build wrote.
#
# Usage:
#   ./scripts/run_android_capi_smoke.sh --serial <adb serial> --version <version> [--repo <m2 path>]
#
#   --repo   default: android/build/m2 (scripts/build_android_library_aar.sh --m2 writes it, and
#            copies it to dist/<version>/android/m2)
#
# What runs, each built only from the repository with R8 (release):
#   smoke <stl> <path>   the instrumented test for each app STL (none, c++_static, c++_shared) and
#                        each initialization path (auto: androidx.startup; manual: ntk_android_init)
#   no keep <path>       the AAR's keep rules dropped: CLASS_NOT_FOUND from C and Kotlin, no crash
#   progress from back   outside instrumentation (which is exempt): starting a progress notification
#                        20 s after the app went to the back is SERVICE_START_NOT_ALLOWED (14)
#   32-bit               installed as armeabi-v7a, where libntk.so is missing: the app runs, the C
#                        ABI says UNAVAILABLE and the Kotlin API works. Skipped on a device without
#                        32-bit ABIs.
#   kotlin <version>     android/android_library_kotlin_consumer (AGP 8.10, Gradle 8.13) compiles
#                        against both AARs with the Kotlin Gradle plugin 2.2.21 and 2.1.21 (README
#                        8.3): their POMs and metadata ask for Kotlin core libraries those read
# The summary lists PASS / FAIL / SKIP per item; the exit status is 1 when anything failed.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
ANDROID_ROOT="${ROOT_DIR}/android"
SMOKE_DIR="android_library_capi_smoke"
PACKAGE="com.jonghyunkim.nativetoolkit.smoke"
RESULTS="${ANDROID_ROOT}/${SMOKE_DIR}/app/build/outputs/androidTest-results"

SERIAL=""
VERSION=""
REPO="${ANDROID_ROOT}/build/m2"

usage() {
  sed -n '4,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial) SERIAL="${2:?--serial needs a value}"; shift 2 ;;
    --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
    --repo) REPO="${2:?--repo needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done
if [[ -z "${SERIAL}" || -z "${VERSION}" ]]; then
  echo "Error: --serial and --version are required." >&2
  usage
  exit 1
fi
if [[ "${REPO}" != /* ]]; then
  REPO="${ROOT_DIR}/${REPO}"
fi
if [[ ! -d "${REPO}/io/github/kimjh4941/android-native-toolkit-capi/${VERSION}" ]]; then
  echo "Error: ${REPO} has no android-native-toolkit-capi ${VERSION}." >&2
  exit 1
fi

for java_home in "/Applications/Android Studio Panda 1 .app/Contents/jbr/Contents/Home" \
                 "/Applications/Android Studio.app/Contents/jbr/Contents/Home"; do
  if [[ -d "${java_home}" ]]; then
    export JAVA_HOME="${java_home}"
    break
  fi
done
# The smoke is a build of its own, without android/local.properties.
export ANDROID_HOME="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
export ANDROID_SERIAL="${SERIAL}"

SUMMARY=()
FAILED=0
record() {
  SUMMARY+=("$1 $2${3:+: $3}")
  if [[ "$1" == "FAIL" ]]; then
    FAILED=1
  fi
}

gradle_smoke() {
  (cd "${ANDROID_ROOT}" && ./gradlew --no-daemon -q -p "${SMOKE_DIR}" -PntkVersion="${VERSION}" -PntkRepo="${REPO}" "$@")
}

# The instrumented test of one build: PASS when it ran with no failure, and skipped no more than
# the case meant for the other kind of build.
instrumented() {
  local name=$1 flavor=$2
  shift 2
  rm -rf "${RESULTS}"
  local task=":app:connected${flavor}ReleaseAndroidTest"
  if ! gradle_smoke "$@" "${task}" >/dev/null 2>&1; then
    true # the result file says what happened
  fi
  local counts
  counts="$(find "${RESULTS}" -name '*.xml' -exec grep -ohE 'tests="[0-9]+" failures="[0-9]+" errors="[0-9]+" skipped="[0-9]+"' {} \; 2>/dev/null | head -1)"
  if [[ "${counts}" == 'tests="2" failures="0" errors="0" skipped="1"' ]]; then
    record PASS "${name}"
  else
    record FAIL "${name}" "${counts:-no result}"
  fi
}

for stl in none c++_static c++_shared; do
  for flavor in Auto Manual; do
    instrumented "smoke ${stl} $(echo "${flavor}" | tr '[:upper:]' '[:lower:]')" "${flavor}" -Pstl="${stl}"
  done
done
for flavor in Auto Manual; do
  instrumented "no keep $(echo "${flavor}" | tr '[:upper:]' '[:lower:]')" "${flavor}" -PnoKeep=true
done

APK="${ANDROID_ROOT}/${SMOKE_DIR}/app/build/outputs/apk/auto/release/app-auto-release.apk"

# Progress from the back, outside instrumentation.
if gradle_smoke :app:assembleAutoRelease >/dev/null 2>&1 && adb install -r -g "${APK}" >/dev/null; then
  adb logcat -c
  adb shell am start -n "${PACKAGE}/.MainActivity" --ez progressFromBack true >/dev/null
  sleep 4
  adb shell input keyevent KEYCODE_HOME
  sleep 28
  line="$(adb logcat -d -s ntk-smoke:I | grep 'progressFromBack:' | tail -1 || true)"
  if [[ "${line}" == *"progressFromBack: 14" ]]; then
    record PASS "progress from back"
  else
    record FAIL "progress from back" "${line:-no result in logcat}"
  fi
else
  record FAIL "progress from back" "could not build or install"
fi

# Installed as 32-bit.
if [[ -z "$(adb shell getprop ro.product.cpu.abilist32 | tr -d '\r')" ]]; then
  record SKIP "32-bit" "the device has no 32-bit ABI"
elif gradle_smoke -Pabi32=true :app:assembleAutoRelease >/dev/null 2>&1; then
  adb uninstall "${PACKAGE}" >/dev/null 2>&1 || true
  if adb install --abi armeabi-v7a -g "${APK}" >/dev/null; then
    adb logcat -c
    adb shell am start -n "${PACKAGE}/.MainActivity" --ez kotlinOnly true >/dev/null
    sleep 6
    line="$(adb logcat -d -s ntk-smoke:I | grep 'kotlinOnly:' | tail -1 || true)"
    abi="$(adb shell dumpsys package "${PACKAGE}" | grep -o 'primaryCpuAbi=[^ ]*' | head -1)"
    alive="$(adb shell pidof "${PACKAGE}" | tr -d '\r' || true)"
    if [[ "${line}" == *"kotlinOnly: capi=UNAVAILABLE, clipboard=true" && "${abi}" == "primaryCpuAbi=armeabi-v7a" && -n "${alive}" ]]; then
      record PASS "32-bit"
    else
      record FAIL "32-bit" "${abi}, alive=${alive:-no}, ${line:-no result in logcat}"
    fi
  else
    record FAIL "32-bit" "could not install as armeabi-v7a"
  fi
else
  record FAIL "32-bit" "could not build"
fi
adb uninstall "${PACKAGE}" >/dev/null 2>&1 || true

# Kotlin consumers on older compilers (no device needed).
for kgp in 2.2.21 2.1.21; do
  consumer="${ANDROID_ROOT}/android_library_kotlin_consumer"
  rm -rf "${consumer}/app/build"
  if (cd "${consumer}" && ./gradlew --no-daemon -q --refresh-dependencies -Pkgp="${kgp}" -PntkVersion="${VERSION}" \
        -PntkRepo="${REPO}" :app:assembleDebug >/dev/null 2>&1) && [[ -f "${consumer}/app/build/outputs/apk/debug/app-debug.apk" ]]; then
    record PASS "kotlin ${kgp}"
  else
    record FAIL "kotlin ${kgp}" "does not compile; run its gradlew for the errors"
  fi
done

echo "== Android C ABI smoke ${VERSION} on ${SERIAL}"
for line in "${SUMMARY[@]}"; do
  echo "  ${line}"
done
exit "${FAILED}"
