#!/usr/bin/env bash
set -euo pipefail

# Build one or more macOS library XCFrameworks and copy them with distributable names.
#
# Usage:
#   ./scripts/build_xcode16_library_xcframework.sh [--module <name>]... [--configuration <debug|release>] [--library-version <version>] [--output <path>]
#
# Examples:
#   ./scripts/build_xcode16_library_xcframework.sh
#   ./scripts/build_xcode16_library_xcframework.sh --configuration debug
#   ./scripts/build_xcode16_library_xcframework.sh --library-version 1.1.0
#   ./scripts/build_xcode16_library_xcframework.sh --module MacLibrary --module UnityMacPlugin --library-version 1.1.0
#   ./scripts/build_xcode16_library_xcframework.sh --configuration release --output dist/1.1.0/mac/mac-native-toolkit-1.1.0.xcframework
#   ./scripts/build_xcode16_library_xcframework.sh -c debug -v 1.1.0 -o /tmp/NativeToolkit-debug.xcframework
#   ./scripts/build_xcode16_library_xcframework.sh -c release -m MacLibrary -m UnityMacPlugin -v 1.1.0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

CONFIGURATION="release"
MODULES=()
OUTPUT_PATH=""
OUTPUT_PATH_SET=false
LIBRARY_VERSION=""

usage() {
  cat <<'USAGE'
Build one or more macOS library XCFrameworks and copy them to target paths.

Usage:
  ./scripts/build_xcode16_library_xcframework.sh [--module <name>]... [--configuration <debug|release>] [--library-version <version>] [--output <path>]

Options:
  -m, --module         Module to build (repeatable). Examples: MacLibrary, UnityMacPlugin
                       Default: MacLibrary
  -c, --configuration  Build configuration (debug or release). Default: release
  -v, --library-version
                       Library version to include in default output naming.
                       Example default with version: dist/<version>/mac/<output-name>-<version>.xcframework
  -o, --output         Output XCFramework path. Relative paths are resolved from repository root.
                       Default (when omitted): per-module default output path
                       MacLibrary:     dist/<version>/mac/mac-native-toolkit-<version>.xcframework
                       UnityMacPlugin: dist/<version>/mac/unity-mac-native-toolkit-<version>.xcframework
                       Note: --library-version is required when --output is omitted.
                       Note: --output is allowed only for single-module builds.
  -h, --help           Show this help message.
USAGE
}

resolve_xcframework_output_name() {
  local module=$1
  case "${module}" in
    MacLibrary)     echo "mac-native-toolkit" ;;
    UnityMacPlugin) echo "unity-mac-native-toolkit" ;;
    *)              echo "${module}" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--module)
      if [[ $# -lt 2 ]]; then
        echo "Error: --module requires a value." >&2
        usage
        exit 1
      fi
      MODULES+=("$2")
      shift 2
      ;;
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

if [[ ${#MODULES[@]} -eq 0 ]]; then
  MODULES=("MacLibrary")
fi

if [[ "${CONFIGURATION}" != "debug" && "${CONFIGURATION}" != "release" ]]; then
  echo "Error: --configuration must be 'debug' or 'release'." >&2
  usage
  exit 1
fi

if [[ "${OUTPUT_PATH_SET}" == "true" && ${#MODULES[@]} -gt 1 ]]; then
  echo "Error: --output is not allowed for multi-module builds." >&2
  usage
  exit 1
fi

if [[ -n "${LIBRARY_VERSION}" ]]; then
  if [[ "${LIBRARY_VERSION}" =~ [[:space:]/] ]]; then
    echo "Error: --library-version must not contain spaces or '/' characters." >&2
    usage
    exit 1
  fi
fi

if [[ "${OUTPUT_PATH_SET}" == "false" && -z "${LIBRARY_VERSION}" ]]; then
  echo "Error: --library-version is required when --output is not specified." >&2
  usage
  exit 1
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
  local project_path=$1
  local scheme=$2
  local current_build_number
  local pbxproj_path="${project_path}/project.pbxproj"

  current_build_number="$(xcodebuild -project "${project_path}" -scheme "${scheme}" -configuration "${XCODE_CONFIGURATION}" -showBuildSettings 2>/dev/null | awk -F' = ' '/CURRENT_PROJECT_VERSION/ {print $2; exit}')"

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

# UnityMacPlugin depends on MacLibrary — ensure MacLibrary is always built first.
_IMPLICIT_MODULES=()
_has_UnityMacPlugin=false
_has_MacLibrary=false
for _m in "${MODULES[@]}"; do
  [[ "${_m}" == "UnityMacPlugin" ]] && _has_UnityMacPlugin=true
  [[ "${_m}" == "MacLibrary" ]] && _has_MacLibrary=true
done
if [[ "${_has_UnityMacPlugin}" == "true" && "${_has_MacLibrary}" == "false" ]]; then
  _IMPLICIT_MODULES+=("MacLibrary")
fi

# Canonical build order: MacLibrary always before UnityMacPlugin.
BUILD_MODULES=()
for _ord_m in MacLibrary UnityMacPlugin; do
  _found_m=false
  for _cm in ${_IMPLICIT_MODULES[@]+"${_IMPLICIT_MODULES[@]}"} "${MODULES[@]}"; do
    [[ "${_cm}" == "${_ord_m}" ]] && _found_m=true && break
  done
  [[ "${_found_m}" == "true" ]] && BUILD_MODULES+=("${_ord_m}")
done

# Track MacLibrary archive path so UnityMacPlugin can use it as FRAMEWORK_SEARCH_PATHS.
_MACLIB_ARCHIVE=""

for MODULE in "${BUILD_MODULES[@]}"; do
  case "${MODULE}" in
    MacLibrary)
      MODULE_WORKSPACE_PATH=""
      MODULE_PROJECT_PATH="${ROOT_DIR}/mac/MacLibrary/MacLibrary.xcodeproj"
      MODULE_SCHEME="MacLibrary"
      MODULE_FRAMEWORK="MacLibrary"
      MODULE_BUILD_ROOT="${ROOT_DIR}/mac/Build/MacLibrary"
      ;;
    UnityMacPlugin)
      MODULE_WORKSPACE_PATH="${ROOT_DIR}/mac/MacWorkspace.xcworkspace"
      MODULE_PROJECT_PATH="${ROOT_DIR}/mac/UnityMacPlugin/UnityMacPlugin.xcodeproj"
      MODULE_SCHEME="UnityMacPlugin"
      MODULE_FRAMEWORK="UnityMacPlugin"
      MODULE_BUILD_ROOT="${ROOT_DIR}/mac/Build/UnityMacPlugin"
      ;;
    *)
      echo "Error: Unknown module '${MODULE}'. Valid modules: MacLibrary, UnityMacPlugin" >&2
      exit 1
      ;;
  esac

  _is_implicit=false
  for _im in ${_IMPLICIT_MODULES[@]+"${_IMPLICIT_MODULES[@]}"}; do
    [[ "${_im}" == "${MODULE}" ]] && _is_implicit=true && break
  done

  MODULE_ARCHIVE_PATH="${MODULE_BUILD_ROOT}/${MODULE_SCHEME}-macOS.xcarchive"
  MODULE_DERIVED_DATA_PATH="${MODULE_BUILD_ROOT}/DerivedData"
  MODULE_ARCHIVE_PRODUCTS_PATH="${MODULE_DERIVED_DATA_PATH}/Build/Intermediates.noindex/ArchiveIntermediates/${MODULE_SCHEME}/BuildProductsPath/${XCODE_CONFIGURATION}"

  if [[ -n "${MODULE_WORKSPACE_PATH}" ]]; then
    if [[ ! -d "${MODULE_WORKSPACE_PATH}" ]]; then
      echo "Error: macOS workspace not found at ${MODULE_WORKSPACE_PATH}" >&2
      exit 1
    fi
    MODULE_XCODE_CONTAINER_ARGS=("-workspace" "${MODULE_WORKSPACE_PATH}")
  else
    if [[ ! -d "${MODULE_PROJECT_PATH}" ]]; then
      echo "Error: macOS project not found at ${MODULE_PROJECT_PATH}" >&2
      exit 1
    fi
    MODULE_XCODE_CONTAINER_ARGS=("-project" "${MODULE_PROJECT_PATH}")
  fi

  MODULE_XCODE_EXTRA_SETTINGS=("${XCODE_EXTRA_SETTINGS[@]}")
  MODULE_NEXT_BUILD_NUMBER=""
  if [[ "${_is_implicit}" == "false" && "${CONFIGURATION}" == "release" ]]; then
    MODULE_NEXT_BUILD_NUMBER="$(resolve_next_build_number "${MODULE_PROJECT_PATH}" "${MODULE_SCHEME}")"
    MODULE_XCODE_EXTRA_SETTINGS+=("CURRENT_PROJECT_VERSION=${MODULE_NEXT_BUILD_NUMBER}")
    echo "[info] [${MODULE}] Increment release build number: ${MODULE_NEXT_BUILD_NUMBER}"
  fi

  if [[ "${_is_implicit}" == "false" && ( -n "${LIBRARY_VERSION}" || "${CONFIGURATION}" == "release" ) ]]; then
    update_pbxproj_versions \
      "${MODULE_PROJECT_PATH}/project.pbxproj" \
      "${LIBRARY_VERSION}" \
      "${MODULE_NEXT_BUILD_NUMBER}"
    echo "[info] [${MODULE}] Updated project.pbxproj: MARKETING_VERSION=${LIBRARY_VERSION:-unchanged} CURRENT_PROJECT_VERSION=${MODULE_NEXT_BUILD_NUMBER:-unchanged}"
  fi

  # Pass MacLibrary framework path to UnityMacPlugin's build so the import can be resolved.
  _build_settings=("${MODULE_XCODE_EXTRA_SETTINGS[@]}")
  if [[ "${MODULE}" == "UnityMacPlugin" && -n "${_MACLIB_ARCHIVE}" ]]; then
    _build_settings+=("FRAMEWORK_SEARCH_PATHS=${_MACLIB_ARCHIVE}/Products/Library/Frameworks")
  fi

  echo "[clean] [${MODULE}] Cleaning previous archive"
  rm -rf "${MODULE_ARCHIVE_PATH}" "${MODULE_DERIVED_DATA_PATH}"

  # UnityMacPlugin embeds MacLibrary from archive BuildProductsPath during install phase.
  if [[ "${MODULE}" == "UnityMacPlugin" && -n "${_MACLIB_ARCHIVE}" ]]; then
    _dep_framework_src="${_MACLIB_ARCHIVE}/Products/Library/Frameworks/MacLibrary.framework"
    _dep_framework_dst="${MODULE_ARCHIVE_PRODUCTS_PATH}/MacLibrary.framework"
    if [[ ! -d "${_dep_framework_src}" ]]; then
      echo "Error: Dependency framework not found at ${_dep_framework_src}" >&2
      exit 1
    fi
    mkdir -p "${MODULE_ARCHIVE_PRODUCTS_PATH}"
    rm -rf "${_dep_framework_dst}"
    ditto "${_dep_framework_src}" "${_dep_framework_dst}"
    echo "[dep] [${MODULE}] Staged MacLibrary.framework at ${_dep_framework_dst}"
  fi

  echo "[archive] [${MODULE}] Building ${MODULE_SCHEME} (${XCODE_CONFIGURATION}) for macOS"
  xcodebuild archive \
    "${MODULE_XCODE_CONTAINER_ARGS[@]}" \
    -scheme "${MODULE_SCHEME}" \
    -configuration "${XCODE_CONFIGURATION}" \
    -destination "generic/platform=macOS" \
    -archivePath "${MODULE_ARCHIVE_PATH}" \
    -derivedDataPath "${MODULE_DERIVED_DATA_PATH}" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    "${_build_settings[@]}"

  if [[ "${MODULE}" == "MacLibrary" ]]; then
    _MACLIB_ARCHIVE="${MODULE_ARCHIVE_PATH}"
  fi

  if [[ "${_is_implicit}" == "true" ]]; then
    echo "[dep] [${MODULE}] Built dependency archive (no xcframework output)"
    continue
  fi

  if [[ "${OUTPUT_PATH_SET}" == "true" ]]; then
    MODULE_OUTPUT_PATH="${OUTPUT_PATH}"
  else
    OUTPUT_PREFIX="$(resolve_xcframework_output_name "${MODULE}")"
    if [[ "${CONFIGURATION}" == "debug" ]]; then
      MODULE_OUTPUT_PATH="dist/${LIBRARY_VERSION}/mac/${OUTPUT_PREFIX}-${LIBRARY_VERSION}-debug.xcframework"
    else
      MODULE_OUTPUT_PATH="dist/${LIBRARY_VERSION}/mac/${OUTPUT_PREFIX}-${LIBRARY_VERSION}.xcframework"
    fi
  fi

  if [[ "${MODULE_OUTPUT_PATH}" = /* ]]; then
    XCFRAMEWORK_TARGET="${MODULE_OUTPUT_PATH}"
  else
    XCFRAMEWORK_TARGET="${ROOT_DIR}/${MODULE_OUTPUT_PATH}"
  fi

  MODULE_FRAMEWORK_PATH="${MODULE_ARCHIVE_PATH}/Products/Library/Frameworks/${MODULE_FRAMEWORK}.framework"

  if [[ ! -d "${MODULE_FRAMEWORK_PATH}" ]]; then
    echo "Error: Framework not found at ${MODULE_FRAMEWORK_PATH}" >&2
    exit 1
  fi

  mkdir -p "$(dirname -- "${XCFRAMEWORK_TARGET}")"
  rm -rf "${XCFRAMEWORK_TARGET}"

  echo "[package] [${MODULE}] Creating XCFramework"
  xcodebuild -create-xcframework \
    -framework "${MODULE_FRAMEWORK_PATH}" \
    -output "${XCFRAMEWORK_TARGET}"

  echo "[done] [${MODULE}] Created ${XCFRAMEWORK_TARGET}"
done
