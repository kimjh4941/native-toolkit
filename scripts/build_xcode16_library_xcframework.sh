#!/usr/bin/env bash
set -euo pipefail

# Build MacLibrary XCFramework and copy it with a distributable name.
#
# Usage:
#   ./scripts/build_xcode16_library_xcframework.sh [--configuration <debug|release>] [--output <path>]
#
# Examples:
#   ./scripts/build_xcode16_library_xcframework.sh
#   ./scripts/build_xcode16_library_xcframework.sh --configuration debug
#   ./scripts/build_xcode16_library_xcframework.sh --configuration release --output dist/NativeToolkit.xcframework
#   ./scripts/build_xcode16_library_xcframework.sh -c debug -o /tmp/NativeToolkit-debug.xcframework

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

CONFIGURATION="release"
OUTPUT_PATH="dist/NativeToolkit.xcframework"

MAC_PROJECT_PATH="${ROOT_DIR}/mac/MacLibrary/MacLibrary.xcodeproj"
MAC_SCHEME="MacLibrary"
BUILD_ROOT="${ROOT_DIR}/mac/Build/MacLibrary"
ARCHIVE_PATH="${BUILD_ROOT}/MacLibrary-macOS.xcarchive"

usage() {
  cat <<'USAGE'
Build MacLibrary XCFramework and copy it to a target path.

Usage:
  ./scripts/build_xcode16_library_xcframework.sh [--configuration <debug|release>] [--output <path>]

Options:
  -c, --configuration  Build configuration (debug or release). Default: release
  -o, --output         Output XCFramework path. Relative paths are resolved from repository root.
                       Default: dist/NativeToolkit.xcframework
  -h, --help           Show this help message.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--configuration)
      if [[ $# -lt 2 ]]; then
        echo "Error: --configuration requires a value." >&2
        usage
        exit 1
      fi
      CONFIGURATION="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
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

if [[ "${CONFIGURATION}" != "debug" && "${CONFIGURATION}" != "release" ]]; then
  echo "Error: --configuration must be 'debug' or 'release'." >&2
  usage
  exit 1
fi

XCODE_CONFIGURATION="Release"
if [[ "${CONFIGURATION}" == "debug" ]]; then
  XCODE_CONFIGURATION="Debug"
fi

if [[ "${OUTPUT_PATH}" = /* ]]; then
  XCFRAMEWORK_TARGET="${OUTPUT_PATH}"
else
  XCFRAMEWORK_TARGET="${ROOT_DIR}/${OUTPUT_PATH}"
fi

if [[ ! -d "${MAC_PROJECT_PATH}" ]]; then
  echo "Error: macOS project not found at ${MAC_PROJECT_PATH}" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild is not available. Install Xcode command line tools." >&2
  exit 1
fi

echo "[clean] Cleaning previous archive"
rm -rf "${ARCHIVE_PATH}"

echo "[archive] Building ${MAC_SCHEME} (${XCODE_CONFIGURATION}) for macOS"
xcodebuild archive \
  -project "${MAC_PROJECT_PATH}" \
  -scheme "${MAC_SCHEME}" \
  -configuration "${XCODE_CONFIGURATION}" \
  -destination "generic/platform=macOS" \
  -archivePath "${ARCHIVE_PATH}" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

MAC_FRAMEWORK="${ARCHIVE_PATH}/Products/Library/Frameworks/MacLibrary.framework"

if [[ ! -d "${MAC_FRAMEWORK}" ]]; then
  echo "Error: Framework not found at ${MAC_FRAMEWORK}" >&2
  exit 1
fi

mkdir -p "$(dirname -- "${XCFRAMEWORK_TARGET}")"
rm -rf "${XCFRAMEWORK_TARGET}"

echo "[package] Creating XCFramework"
xcodebuild -create-xcframework \
  -framework "${MAC_FRAMEWORK}" \
  -output "${XCFRAMEWORK_TARGET}"

echo "[done] Created ${XCFRAMEWORK_TARGET}"
