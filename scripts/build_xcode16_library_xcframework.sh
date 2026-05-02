#!/usr/bin/env bash
set -euo pipefail

# Build MacLibrary XCFramework and copy it with a distributable name.
#
# Usage:
#   ./scripts/build_xcode16_library_xcframework.sh [--configuration <debug|release>] [--library-version <version>] [--output <path>]
#
# Examples:
#   ./scripts/build_xcode16_library_xcframework.sh
#   ./scripts/build_xcode16_library_xcframework.sh --configuration debug
#   ./scripts/build_xcode16_library_xcframework.sh --library-version 1.1.0
#   ./scripts/build_xcode16_library_xcframework.sh --configuration release --output dist/1.1.0/mac/NativeToolkit-1.1.0.xcframework
#   ./scripts/build_xcode16_library_xcframework.sh -c debug -v 1.1.0 -o /tmp/NativeToolkit-debug.xcframework

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

CONFIGURATION="release"
OUTPUT_PATH="dist/NativeToolkit.xcframework"
OUTPUT_PATH_SET=false
LIBRARY_VERSION=""

MAC_PROJECT_PATH="${ROOT_DIR}/mac/MacLibrary/MacLibrary.xcodeproj"
MAC_SCHEME="MacLibrary"
BUILD_ROOT="${ROOT_DIR}/mac/Build/MacLibrary"
ARCHIVE_PATH="${BUILD_ROOT}/MacLibrary-macOS.xcarchive"

usage() {
  cat <<'USAGE'
Build MacLibrary XCFramework and copy it to a target path.

Usage:
  ./scripts/build_xcode16_library_xcframework.sh [--configuration <debug|release>] [--library-version <version>] [--output <path>]

Options:
  -c, --configuration  Build configuration (debug or release). Default: release
  -v, --library-version
                       Library version to include in default output naming.
                       Example default with version: dist/<version>/mac/NativeToolkit-<version>.xcframework
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
      OUTPUT_PATH_SET=true
      shift 2
      ;;
    -v|--library-version)
      if [[ $# -lt 2 ]]; then
        echo "Error: --library-version requires a value." >&2
        usage
        exit 1
      fi
      LIBRARY_VERSION="$2"
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

if [[ -n "${LIBRARY_VERSION}" ]]; then
  if [[ "${LIBRARY_VERSION}" =~ [[:space:]/] ]]; then
    echo "Error: --library-version must not contain spaces or '/' characters." >&2
    usage
    exit 1
  fi
  if [[ "${OUTPUT_PATH_SET}" == "false" ]]; then
    OUTPUT_PATH="dist/${LIBRARY_VERSION}/mac/NativeToolkit-${LIBRARY_VERSION}.xcframework"
  fi
fi

XCODE_CONFIGURATION="Release"
if [[ "${CONFIGURATION}" == "debug" ]]; then
  XCODE_CONFIGURATION="Debug"
fi

XCODE_EXTRA_SETTINGS=()
if [[ -n "${LIBRARY_VERSION}" ]]; then
  XCODE_EXTRA_SETTINGS+=("MARKETING_VERSION=${LIBRARY_VERSION}")
  echo "[info] Override framework marketing version: ${LIBRARY_VERSION}"
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

ensure_xcode_developer_dir() {
  local current_developer_dir
  local detected_xcode_dir

  current_developer_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    return
  fi

  if [[ "${current_developer_dir}" == "/Library/Developer/CommandLineTools" ]]; then
    detected_xcode_dir="$(ls -d /Applications/Xcode*.app/Contents/Developer 2>/dev/null | head -n 1 || true)"
    if [[ -n "${detected_xcode_dir}" ]]; then
      export DEVELOPER_DIR="${detected_xcode_dir}"
      echo "[info] Using DEVELOPER_DIR=${DEVELOPER_DIR}"
    fi
  fi
}

ensure_xcode_developer_dir

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild is not available. Install Xcode command line tools." >&2
  exit 1
fi

resolve_next_build_number() {
  local current_build_number
  local pbxproj_path="${MAC_PROJECT_PATH}/project.pbxproj"

  current_build_number="$(xcodebuild -project "${MAC_PROJECT_PATH}" -scheme "${MAC_SCHEME}" -configuration "${XCODE_CONFIGURATION}" -showBuildSettings 2>/dev/null | awk -F' = ' '/CURRENT_PROJECT_VERSION/ {print $2; exit}')"

  if [[ -z "${current_build_number}" && -f "${pbxproj_path}" ]]; then
    current_build_number="$(awk -F'[=;]' '/CURRENT_PROJECT_VERSION/ {gsub(/[[:space:]]/, "", $2); if ($2 ~ /^[0-9]+$/) {print $2; exit}}' "${pbxproj_path}")"
    if [[ -n "${current_build_number}" ]]; then
      echo "[warn] Using CURRENT_PROJECT_VERSION from project.pbxproj fallback: ${current_build_number}" >&2
    fi
  fi

  if [[ -z "${current_build_number}" ]]; then
    echo "Error: Could not resolve CURRENT_PROJECT_VERSION from Xcode build settings or project.pbxproj." >&2
    echo "Hint: If Xcode is installed, run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
  fi

  if [[ ! "${current_build_number}" =~ ^[0-9]+$ ]]; then
    echo "Error: CURRENT_PROJECT_VERSION must be an integer to auto-increment (current: ${current_build_number})." >&2
    exit 1
  fi

  printf '%s' "$((current_build_number + 1))"
}

update_pbxproj_versions() {
  local pbxproj_path=$1
  local new_version="${2:-}"
  local new_build_number="${3:-}"
  local tmp_file

  if [[ ! -f "${pbxproj_path}" ]]; then
    echo "Error: project.pbxproj not found at ${pbxproj_path}" >&2
    exit 1
  fi

  tmp_file="$(mktemp)"
  awk -v version="${new_version}" -v build="${new_build_number}" '
    /MARKETING_VERSION[[:space:]]*=/ && version != "" {
      gsub(/MARKETING_VERSION[[:space:]]*=[[:space:]]*[^;]*;/, "MARKETING_VERSION = " version ";")
    }
    /CURRENT_PROJECT_VERSION[[:space:]]*=/ && build != "" {
      gsub(/CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*[^;]*;/, "CURRENT_PROJECT_VERSION = " build ";")
    }
    { print }
  ' "${pbxproj_path}" > "${tmp_file}"
  mv "${tmp_file}" "${pbxproj_path}"
}

if [[ "${CONFIGURATION}" == "release" ]]; then
  NEXT_BUILD_NUMBER="$(resolve_next_build_number)"
  XCODE_EXTRA_SETTINGS+=("CURRENT_PROJECT_VERSION=${NEXT_BUILD_NUMBER}")
  echo "[info] Increment release build number: ${NEXT_BUILD_NUMBER}"
fi

if [[ -n "${LIBRARY_VERSION}" || "${CONFIGURATION}" == "release" ]]; then
  update_pbxproj_versions \
    "${MAC_PROJECT_PATH}/project.pbxproj" \
    "${LIBRARY_VERSION}" \
    "${NEXT_BUILD_NUMBER:-}"
  echo "[info] Updated project.pbxproj: MARKETING_VERSION=${LIBRARY_VERSION:-unchanged} CURRENT_PROJECT_VERSION=${NEXT_BUILD_NUMBER:-unchanged}"
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
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  "${XCODE_EXTRA_SETTINGS[@]}"

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
