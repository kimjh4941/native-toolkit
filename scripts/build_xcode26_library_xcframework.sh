#!/usr/bin/env bash
set -euo pipefail

# Build MacLibrary XCFramework and copy it with a distributable name.
#
# Usage:
#   ./scripts/build_xcode26_library_xcframework.sh [--configuration <debug|release>] [--output <path>] [--minimum-macos <version>]
#
# Examples:
#   ./scripts/build_xcode26_library_xcframework.sh
#   ./scripts/build_xcode26_library_xcframework.sh --configuration debug
#   ./scripts/build_xcode26_library_xcframework.sh --configuration release --output dist/NativeToolkit.xcframework
#   ./scripts/build_xcode26_library_xcframework.sh -c debug -o /tmp/NativeToolkit-debug.xcframework -m 15.0

# Resolve script/workspace root paths.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && /bin/pwd -P)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && /bin/pwd -P)"

# Default options (can be overridden by CLI arguments).
CONFIGURATION="release"
OUTPUT_PATH="dist/NativeToolkit.xcframework"
MINIMUM_MACOS="15.0"

# macOS library project/build locations.
MAC_PROJECT_PATH="${ROOT_DIR}/mac/MacLibrary/MacLibrary.xcodeproj"
MAC_SCHEME="MacLibrary"
BUILD_ROOT="${ROOT_DIR}/mac/Build/MacLibrary"
ARCHIVE_PATH="${BUILD_ROOT}/MacLibrary-macOS.xcarchive"
DERIVED_DATA_PATH="${BUILD_ROOT}/DerivedData"

# Print command usage.
usage() {
  echo "Usage: ./scripts/build_xcode26_library_xcframework.sh [--configuration <debug|release>] [--output <path>] [--minimum-macos <version>]"
  echo "  -c, --configuration  debug or release (default: release)"
  echo "  -o, --output         output xcframework path (default: dist/NativeToolkit.xcframework)"
  echo "  -m, --minimum-macos  minimum macOS version >= 15.0 (default: 15.0)"
  echo "  -h, --help           show help"
}

# Parse CLI arguments.
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--configuration) CONFIGURATION="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"; shift 2 ;;
    -o|--output) OUTPUT_PATH="$2"; shift 2 ;;
    -m|--minimum-macos) MINIMUM_MACOS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# Validate option values.
if [[ "${CONFIGURATION}" != "debug" && "${CONFIGURATION}" != "release" ]]; then
  echo "Error: --configuration must be 'debug' or 'release'." >&2
  exit 1
fi

if [[ ! "${MINIMUM_MACOS}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Error: --minimum-macos must be numeric (e.g. 15.0)." >&2
  exit 1
fi

# Map script configuration to Xcode configuration.
XCODE_CONFIGURATION="Release"
[[ "${CONFIGURATION}" == "debug" ]] && XCODE_CONFIGURATION="Debug"

# Resolve output to absolute path.
if [[ "${OUTPUT_PATH}" = /* ]]; then
  XCFRAMEWORK_TARGET="${OUTPUT_PATH}"
else
  XCFRAMEWORK_TARGET="${ROOT_DIR}/${OUTPUT_PATH}"
fi

# Preflight checks.
if [[ ! -d "${MAC_PROJECT_PATH}" ]]; then
  echo "Error: macOS project not found at ${MAC_PROJECT_PATH}" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild is not available." >&2
  exit 1
fi

# Clean previous build artifacts.
echo "[clean] Cleaning previous build root"
rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_ROOT}"

# Archive the macOS framework.
echo "[archive] Building ${MAC_SCHEME} (${XCODE_CONFIGURATION}) for macOS (min ${MINIMUM_MACOS})"
xcodebuild archive \
  -project "${MAC_PROJECT_PATH}" \
  -scheme "${MAC_SCHEME}" \
  -configuration "${XCODE_CONFIGURATION}" \
  -destination "generic/platform=macOS" \
  -archivePath "${ARCHIVE_PATH}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  ENABLE_MODULE_VERIFIER=NO \
  MACOSX_DEPLOYMENT_TARGET="${MINIMUM_MACOS}"

# Validate archived framework output.
MAC_FRAMEWORK="${ARCHIVE_PATH}/Products/Library/Frameworks/MacLibrary.framework"
if [[ ! -d "${MAC_FRAMEWORK}" ]]; then
  echo "Error: Framework not found at ${MAC_FRAMEWORK}" >&2
  exit 1
fi

# Package as XCFramework using a temporary staged framework.
mkdir -p "$(dirname -- "${XCFRAMEWORK_TARGET}")"
echo "[package] Creating XCFramework (staged framework mode)"
PACKAGING_TMP_DIR="$(mktemp -d /tmp/maclibrary-xcframework.XXXXXX)"
STAGED_FRAMEWORK="${PACKAGING_TMP_DIR}/MacLibrary.framework"
TMP_XCFRAMEWORK="${PACKAGING_TMP_DIR}/NativeToolkit.xcframework"
ditto "${MAC_FRAMEWORK}" "${STAGED_FRAMEWORK}"

# Create XCFramework from staged framework.
if ! xcodebuild -create-xcframework \
  -framework "${STAGED_FRAMEWORK}" \
  -output "${TMP_XCFRAMEWORK}"; then
  rm -rf "${PACKAGING_TMP_DIR}"
  echo "Error: Failed to create XCFramework." >&2
  exit 1
fi

# Detect generated slice directory name (e.g. macos-arm64_x86_64).
SLICE_DIR="$(find "${TMP_XCFRAMEWORK}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [[ -z "${SLICE_DIR}" ]]; then
  rm -rf "${PACKAGING_TMP_DIR}"
  echo "Error: XCFramework slice directory not found." >&2
  exit 1
fi
SLICE_NAME="$(basename -- "${SLICE_DIR}")"

# Sync generated XCFramework contents to target path.
mkdir -p "${XCFRAMEWORK_TARGET}/${SLICE_NAME}/MacLibrary.framework"
cp "${TMP_XCFRAMEWORK}/Info.plist" "${XCFRAMEWORK_TARGET}/Info.plist"
rsync -aL --delete "${SLICE_DIR}/MacLibrary.framework/" "${XCFRAMEWORK_TARGET}/${SLICE_NAME}/MacLibrary.framework/"

# Cleanup temporary packaging directory.
rm -rf "${PACKAGING_TMP_DIR}"

echo "[done] Created ${XCFRAMEWORK_TARGET}"
