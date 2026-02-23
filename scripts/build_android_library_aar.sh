#!/usr/bin/env bash
set -euo pipefail

# Build android_library AAR and copy it with a distributable name.
#
# Usage:
#   ./scripts/build_android_library_aar.sh [--build-type <debug|release>] [--output <path>]
#
# Examples:
#   ./scripts/build_android_library_aar.sh
#   ./scripts/build_android_library_aar.sh --build-type debug
#   ./scripts/build_android_library_aar.sh --build-type release --output dist/NativeToolkit-release.aar
#   ./scripts/build_android_library_aar.sh -b debug -o /tmp/NativeToolkit-debug.aar

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

ANDROID_EXAMPLE_DIR="${ROOT_DIR}/android/AndroidLibraryExample"

BUILD_TYPE="release"
OUTPUT_PATH="dist/NativeToolkit.aar"

usage() {
  cat <<'USAGE'
Build android_library AAR and copy it to a target path.

Usage:
  ./scripts/build_android_library_aar.sh [--build-type <debug|release>] [--output <path>]

Options:
  -b, --build-type   Build type to assemble (debug or release). Default: release
  -o, --output       Output AAR path. Relative paths are resolved from repository root.
                     Default: dist/NativeToolkit.aar
  -h, --help         Show this help message.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--build-type)
      if [[ $# -lt 2 ]]; then
        echo "Error: --build-type requires a value." >&2
        usage
        exit 1
      fi
      BUILD_TYPE="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
      shift 2
      ;;
    -o|--output)
      if [[ $# -lt 2 ]]; then
        echo "Error: --output requires a value." >&2
        usage
        exit 1
      fi
      OUTPUT_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "${BUILD_TYPE}" != "debug" && "${BUILD_TYPE}" != "release" ]]; then
  echo "Error: --build-type must be 'debug' or 'release'." >&2
  usage
  exit 1
fi

if [[ "${OUTPUT_PATH}" = /* ]]; then
  AAR_TARGET="${OUTPUT_PATH}"
else
  AAR_TARGET="${ROOT_DIR}/${OUTPUT_PATH}"
fi

AAR_SOURCE="${ROOT_DIR}/android/android_library/build/outputs/aar/android_library-${BUILD_TYPE}.aar"

GRADLE_TASK=":android_library:assembleRelease"
if [[ "${BUILD_TYPE}" == "debug" ]]; then
  GRADLE_TASK=":android_library:assembleDebug"
fi

if [[ ! -x "${ANDROID_EXAMPLE_DIR}/gradlew" ]]; then
  echo "Error: Gradle wrapper not found at ${ANDROID_EXAMPLE_DIR}/gradlew" >&2
  exit 1
fi

echo "[build] Building android_library ${BUILD_TYPE} AAR"
(cd "${ANDROID_EXAMPLE_DIR}" && ./gradlew "${GRADLE_TASK}")

if [[ ! -f "${AAR_SOURCE}" ]]; then
  echo "Error: AAR not found at ${AAR_SOURCE}" >&2
  exit 1
fi

mkdir -p "$(dirname -- "${AAR_TARGET}")"
cp "${AAR_SOURCE}" "${AAR_TARGET}"

echo "[done] Created ${AAR_TARGET}"
