#!/usr/bin/env bash
set -euo pipefail

# Build one or more iOS library XCFrameworks and copy them with distributable names.
#
# Usage:
#   ./scripts/build_ios_library_xcframework.sh [--module <name>]... [--configuration <debug|release>] [--library-version <version>]
#                                              [--output <path> | --output-dir <folder>] [--build-dir <folder>] [--keep-project-versions]
#
# Examples:
#   ./scripts/build_ios_library_xcframework.sh
#   ./scripts/build_ios_library_xcframework.sh --configuration debug
#   ./scripts/build_ios_library_xcframework.sh --library-version 1.2.0
#   ./scripts/build_ios_library_xcframework.sh --module IosLibrary --module UnityIosPlugin --library-version 1.2.0
#   ./scripts/build_ios_library_xcframework.sh --configuration release --output dist/1.6.0/ios/ios-native-toolkit-1.2.0.xcframework
#   ./scripts/build_ios_library_xcframework.sh -c debug -v 1.2.0 -o /tmp/NativeToolkit-debug.xcframework
#   ./scripts/build_ios_library_xcframework.sh -c release -m IosLibrary -v 1.3.0 -o dist/1.9.0/ios/ios-native-toolkit-1.3.0.xcframework
#   ./scripts/build_ios_library_xcframework.sh -c release -m UnityIosPlugin -v 1.3.0 -o dist/1.9.0/ios/unity-ios-native-toolkit-1.3.0.xcframework
#   ./scripts/build_ios_library_xcframework.sh -m IosLibrary -m IosLibraryCApi -v 2.0.0 --output-dir /tmp/ntk-ios \
#       --build-dir /tmp/ntk-ios-build --keep-project-versions
#
# Every framework is archived with CODE_SIGNING_ALLOWED=NO: the distributable frameworks are not
# signed; the app that embeds them signs them (artifact/topics/ios-c-abi/README.md, D-18).
# IosLibraryCApi is Release only (C ABI design part 1, 5.4: Debug installs the Swift module and
# exports _$s14IosLibraryCApi* for @testable import), is compiled against the IosLibrary archive this
# run makes (the IosLibrary that ships with it), and comes with its public headers in
# include/NativeToolkitC/ next to the xcframework. Check the result with scripts/check_ios_dist.py.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

CONFIGURATION="release"
MODULES=()
OUTPUT_PATH=""
OUTPUT_PATH_SET=false
OUTPUT_DIR=""
BUILD_DIR=""
KEEP_PROJECT_VERSIONS=false
LIBRARY_VERSION=""

usage() {
  cat <<'USAGE'
Build one or more iOS library XCFrameworks and copy them to target paths.

Usage:
  ./scripts/build_ios_library_xcframework.sh [--module <name>]... [--configuration <debug|release>] [--library-version <version>]
                                             [--output <path> | --output-dir <folder>] [--build-dir <folder>] [--keep-project-versions]

Options:
  -m, --module         Module to build (repeatable). Examples: IosLibrary, IosLibraryCApi, UnityIosPlugin
                       Default: IosLibrary
                       IosLibraryCApi builds IosLibrary first (as a dependency when it is not asked for)
                       and is release only. Its public headers go to include/NativeToolkitC/ in the
                       folder of its xcframework. Alone (-m IosLibraryCApi) it packages only the capi:
                       the IosLibrary it was built against is not packaged; give -m IosLibrary too for
                       the pair that ships. That folder may not be or hold the tree's headers.
  -c, --configuration  Build configuration (debug or release). Default: release
  -v, --library-version
                       Library version to include in default output naming.
                       Example default with version: dist/<version>/ios/<output-name>-<version>.xcframework
  -o, --output         Output XCFramework path. Relative paths are resolved from repository root.
                       Default (when omitted): per-module default output path
                       IosLibrary:     dist/<version>/ios/ios-native-toolkit-<version>.xcframework
                       UnityIosPlugin: dist/<version>/ios/unity-ios-native-toolkit-<version>.xcframework
                       IosLibraryCApi: dist/<version>/ios/ios-native-toolkit-capi-<version>.xcframework
                       Note: --library-version is required when --output is omitted.
                       Note: --output is allowed only for single-module builds.
      --output-dir     Folder that receives every module's <output-name>-<version>.xcframework (and
                       include/NativeToolkitC/ for IosLibraryCApi), in place of dist/<version>/ios/.
                       Relative paths are resolved from repository root. Needs --library-version.
      --build-dir      Folder for the intermediate archives. Default: ios/Build/<module>
      --keep-project-versions
                       Do not write MARKETING_VERSION and CURRENT_PROJECT_VERSION into the projects
                       and do not increment the build number (a build that is not a release).
                       --library-version still sets the version of what is built.
  -h, --help           Show this help message.
USAGE
}

resolve_xcframework_output_name() {
  local module=$1
  case "${module}" in
    IosLibrary)     echo "ios-native-toolkit" ;;
    IosLibraryCApi) echo "ios-native-toolkit-capi" ;;
    UnityIosPlugin) echo "unity-ios-native-toolkit" ;;
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
    --output-dir)
      if [[ $# -lt 2 ]]; then
        echo "Error: --output-dir requires a value." >&2
        usage
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --build-dir)
      if [[ $# -lt 2 ]]; then
        echo "Error: --build-dir requires a value." >&2
        usage
        exit 1
      fi
      BUILD_DIR="$2"
      shift 2
      ;;
    --keep-project-versions)
      KEEP_PROJECT_VERSIONS=true
      shift
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
  MODULES=("IosLibrary")
fi

if [[ "${CONFIGURATION}" != "debug" && "${CONFIGURATION}" != "release" ]]; then
  echo "Error: --configuration must be 'debug' or 'release'." >&2
  usage
  exit 1
fi

if [[ "${OUTPUT_PATH_SET}" == "true" && -n "${OUTPUT_DIR}" ]]; then
  echo "Error: --output and --output-dir cannot be used together." >&2
  usage
  exit 1
fi

if [[ -n "${OUTPUT_DIR}" && -z "${LIBRARY_VERSION}" ]]; then
  echo "Error: --output-dir needs --library-version, which names the xcframeworks." >&2
  usage
  exit 1
fi

for _m in "${MODULES[@]}"; do
  if [[ "${_m}" == "IosLibraryCApi" && "${CONFIGURATION}" != "release" ]]; then
    # Debug installs the capi's Swift module and exports its Swift symbols for @testable import
    # (C ABI design part 1, 5.4); only Release may ship.
    echo "Error: IosLibraryCApi is built in release only." >&2
    exit 1
  fi
done

resolve_root_path() {
  if [[ "$1" = /* ]]; then
    printf '%s' "$1"
  else
    printf '%s' "${ROOT_DIR}/$1"
  fi
}

# The tree's public headers, which IosLibraryCApi copies next to its xcframework.
HEADERS_SOURCE="${ROOT_DIR}/ios/IosLibraryCApi/include/NativeToolkitC"

# The physical path of a path that may not exist yet: its deepest existing folder with symbolic
# links resolved, then the rest. Fails on a "." or ".." in the part that does not exist.
physical_path() {
  local existing=$1 rest=""
  while [[ ! -d "${existing}" ]]; do
    case "$(basename -- "${existing}")" in
      .|..) return 1 ;;
    esac
    rest="/$(basename -- "${existing}")${rest}"
    existing="$(dirname -- "${existing}")"
  done
  printf '%s%s' "$(cd -P -- "${existing}" && pwd -P)" "${rest}"
}

# Whether $1, or a folder that holds it, is the same folder as $2. -ef compares the device and the inode,
# so a path that names the folder in another case (a case-insensitive file system), through a symbolic
# link or with .. still matches, as rm -rf would resolve it. $1 is a physical path, so its parents are
# found by name.
same_or_inside() {
  local path=$1 parent
  while :; do
    if [[ -e "${path}" && "${path}" -ef "$2" ]]; then
      return 0
    fi
    parent="$(dirname -- "${path}")"
    if [[ "${parent}" == "${path}" ]]; then
      return 1
    fi
    path=${parent}
  done
}

# Stops before the copy of the headers could delete them: the folder the copy replaces must be
# neither the tree's headers nor inside them nor around them, symbolic links included.
guard_headers_target() {
  local target source
  if ! target="$(physical_path "$1")"; then
    echo "Error: cannot resolve ${1} to a physical path; give an output path without . or .. parts." >&2
    exit 1
  fi
  source="$(physical_path "${HEADERS_SOURCE}")"
  if same_or_inside "${target}" "${source}" || same_or_inside "${source}" "${target}"; then
    echo "Error: the headers would be copied to ${1}, which is or holds the tree's headers (${HEADERS_SOURCE})." >&2
    exit 1
  fi
}

# Checked before anything is built: where the capi's loose headers would go.
for _m in "${MODULES[@]}"; do
  if [[ "${_m}" == "IosLibraryCApi" ]]; then
    if [[ "${OUTPUT_PATH_SET}" == "true" ]]; then
      guard_headers_target "$(dirname -- "$(resolve_root_path "${OUTPUT_PATH}")")/include/NativeToolkitC"
    elif [[ -n "${OUTPUT_DIR}" ]]; then
      guard_headers_target "$(resolve_root_path "${OUTPUT_DIR}")/include/NativeToolkitC"
    else
      guard_headers_target "${ROOT_DIR}/dist/${LIBRARY_VERSION}/ios/include/NativeToolkitC"
    fi
  fi
done

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

# The distributable frameworks are not signed (README D-18, A): the app that embeds them signs them.
# The simulator slices still carry the linker's ad-hoc signature, which nothing can leave out.
XCODE_EXTRA_SETTINGS=("CODE_SIGNING_ALLOWED=NO")
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

# UnityIosPlugin and IosLibraryCApi depend on IosLibrary — ensure IosLibrary is always built first.
# If either is requested but IosLibrary is not, add IosLibrary as implicit dep.
_IMPLICIT_MODULES=()
_has_dependent=false
_has_IosLibrary=false
for _m in "${MODULES[@]}"; do
  [[ "${_m}" == "UnityIosPlugin" || "${_m}" == "IosLibraryCApi" ]] && _has_dependent=true
  [[ "${_m}" == "IosLibrary" ]] && _has_IosLibrary=true
done
if [[ "${_has_dependent}" == "true" && "${_has_IosLibrary}" == "false" ]]; then
  _IMPLICIT_MODULES+=("IosLibrary")
fi

# Canonical build order: IosLibrary always before IosLibraryCApi and UnityIosPlugin.
BUILD_MODULES=()
for _ord_m in IosLibrary IosLibraryCApi UnityIosPlugin; do
  _found_m=false
  for _cm in ${_IMPLICIT_MODULES[@]+"${_IMPLICIT_MODULES[@]}"} "${MODULES[@]}"; do
    [[ "${_cm}" == "${_ord_m}" ]] && _found_m=true && break
  done
  [[ "${_found_m}" == "true" ]] && BUILD_MODULES+=("${_ord_m}")
done

# Track IosLibrary archive paths so UnityIosPlugin can use them as FRAMEWORK_SEARCH_PATHS.
_IOSLIB_DEVICE_ARCHIVE=""
_IOSLIB_SIM_ARCHIVE=""

for MODULE in "${BUILD_MODULES[@]}"; do
  case "${MODULE}" in
    IosLibrary)
      MODULE_PROJECT_PATH="${ROOT_DIR}/ios/IosLibrary/IosLibrary.xcodeproj"
      MODULE_SCHEME="IosLibrary"
      MODULE_FRAMEWORK="IosLibrary"
      MODULE_BUILD_ROOT="${ROOT_DIR}/ios/Build/IosLibrary"
      ;;
    IosLibraryCApi)
      MODULE_PROJECT_PATH="${ROOT_DIR}/ios/IosLibraryCApi/IosLibraryCApi.xcodeproj"
      MODULE_SCHEME="IosLibraryCApi"
      MODULE_FRAMEWORK="IosLibraryCApi"
      MODULE_BUILD_ROOT="${ROOT_DIR}/ios/Build/IosLibraryCApi"
      ;;
    UnityIosPlugin)
      MODULE_PROJECT_PATH="${ROOT_DIR}/ios/UnityIosPlugin/UnityIosPlugin.xcodeproj"
      MODULE_SCHEME="UnityIosPlugin"
      MODULE_FRAMEWORK="UnityIosPlugin"
      MODULE_BUILD_ROOT="${ROOT_DIR}/ios/Build/UnityIosPlugin"
      ;;
    *)
      echo "Error: Unknown module '${MODULE}'. Valid modules: IosLibrary, IosLibraryCApi, UnityIosPlugin" >&2
      exit 1
      ;;
  esac

  # Implicit modules are built only as dependencies — no pbxproj update, no xcframework output.
  _is_implicit=false
  for _im in ${_IMPLICIT_MODULES[@]+"${_IMPLICIT_MODULES[@]}"}; do
    [[ "${_im}" == "${MODULE}" ]] && _is_implicit=true && break
  done

  if [[ -n "${BUILD_DIR}" ]]; then
    MODULE_BUILD_ROOT="$(resolve_root_path "${BUILD_DIR}")/${MODULE}"
  fi
  MODULE_DEVICE_ARCHIVE_PATH="${MODULE_BUILD_ROOT}/${MODULE_SCHEME}-iOS.xcarchive"
  MODULE_SIM_ARCHIVE_PATH="${MODULE_BUILD_ROOT}/${MODULE_SCHEME}-Simulator.xcarchive"

  if [[ ! -d "${MODULE_PROJECT_PATH}" ]]; then
    echo "Error: iOS project not found at ${MODULE_PROJECT_PATH}" >&2
    exit 1
  fi

  MODULE_XCODE_EXTRA_SETTINGS=("${XCODE_EXTRA_SETTINGS[@]}")
  MODULE_NEXT_BUILD_NUMBER=""
  if [[ "${_is_implicit}" == "false" && "${CONFIGURATION}" == "release" && "${KEEP_PROJECT_VERSIONS}" == "false" ]]; then
    MODULE_NEXT_BUILD_NUMBER="$(resolve_next_build_number "${MODULE_PROJECT_PATH}" "${MODULE_SCHEME}")"
    MODULE_XCODE_EXTRA_SETTINGS+=("CURRENT_PROJECT_VERSION=${MODULE_NEXT_BUILD_NUMBER}")
    echo "[info] [${MODULE}] Increment release build number: ${MODULE_NEXT_BUILD_NUMBER}"
  fi

  if [[ "${_is_implicit}" == "false" && "${KEEP_PROJECT_VERSIONS}" == "false" && ( -n "${LIBRARY_VERSION}" || "${CONFIGURATION}" == "release" ) ]]; then
    update_pbxproj_versions \
      "${MODULE_PROJECT_PATH}/project.pbxproj" \
      "${LIBRARY_VERSION}" \
      "${MODULE_NEXT_BUILD_NUMBER}"
    echo "[info] [${MODULE}] Updated project.pbxproj: MARKETING_VERSION=${LIBRARY_VERSION:-unchanged} CURRENT_PROJECT_VERSION=${MODULE_NEXT_BUILD_NUMBER:-unchanged}"
  fi

  # Pass IosLibrary framework path to the dependent module's build so the import can be resolved.
  # IosLibraryCApi is compiled against the IosLibrary that ships with it (library evolution), not the
  # one a workspace build would put in its build products.
  _device_build_settings=("${MODULE_XCODE_EXTRA_SETTINGS[@]}")
  _sim_build_settings=("${MODULE_XCODE_EXTRA_SETTINGS[@]}")
  if [[ ( "${MODULE}" == "UnityIosPlugin" || "${MODULE}" == "IosLibraryCApi" ) && -n "${_IOSLIB_DEVICE_ARCHIVE}" ]]; then
    # Quoted inside the value: Xcode splits a list setting at spaces.
    _device_build_settings+=("FRAMEWORK_SEARCH_PATHS=\"${_IOSLIB_DEVICE_ARCHIVE}/Products/Library/Frameworks\"")
    _sim_build_settings+=("FRAMEWORK_SEARCH_PATHS=\"${_IOSLIB_SIM_ARCHIVE}/Products/Library/Frameworks\"")
  fi
  # The capi keeps its project's BUILD_LIBRARY_FOR_DISTRIBUTION=NO (C ABI design part 1, 5.4, P1-19):
  # it ships no Swift module, so there is no interface to keep stable.
  _distribution_setting=("BUILD_LIBRARY_FOR_DISTRIBUTION=YES")
  if [[ "${MODULE}" == "IosLibraryCApi" ]]; then
    _distribution_setting=()
  fi

  echo "[clean] [${MODULE}] Cleaning previous archives"
  rm -rf "${MODULE_DEVICE_ARCHIVE_PATH}" "${MODULE_SIM_ARCHIVE_PATH}"

  echo "[archive] [${MODULE}] Building ${MODULE_SCHEME} (${XCODE_CONFIGURATION}) for iOS devices"
  xcodebuild archive \
    -project "${MODULE_PROJECT_PATH}" \
    -scheme "${MODULE_SCHEME}" \
    -configuration "${XCODE_CONFIGURATION}" \
    -destination "generic/platform=iOS" \
    -archivePath "${MODULE_DEVICE_ARCHIVE_PATH}" \
    SKIP_INSTALL=NO \
    ${_distribution_setting[@]+"${_distribution_setting[@]}"} \
    "${_device_build_settings[@]}"

  echo "[archive] [${MODULE}] Building ${MODULE_SCHEME} (${XCODE_CONFIGURATION}) for iOS Simulator"
  xcodebuild archive \
    -project "${MODULE_PROJECT_PATH}" \
    -scheme "${MODULE_SCHEME}" \
    -configuration "${XCODE_CONFIGURATION}" \
    -destination "generic/platform=iOS Simulator" \
    -archivePath "${MODULE_SIM_ARCHIVE_PATH}" \
    SKIP_INSTALL=NO \
    ${_distribution_setting[@]+"${_distribution_setting[@]}"} \
    "${_sim_build_settings[@]}"

  # Record IosLibrary archive paths for use as dependency by UnityIosPlugin.
  if [[ "${MODULE}" == "IosLibrary" ]]; then
    _IOSLIB_DEVICE_ARCHIVE="${MODULE_DEVICE_ARCHIVE_PATH}"
    _IOSLIB_SIM_ARCHIVE="${MODULE_SIM_ARCHIVE_PATH}"
  fi

  if [[ "${_is_implicit}" == "true" ]]; then
    echo "[dep] [${MODULE}] Built dependency archives (no xcframework output)"
    continue
  fi

  if [[ "${OUTPUT_PATH_SET}" == "true" ]]; then
    MODULE_OUTPUT_PATH="${OUTPUT_PATH}"
  elif [[ -n "${OUTPUT_DIR}" ]]; then
    MODULE_OUTPUT_PATH="$(resolve_root_path "${OUTPUT_DIR}")/$(resolve_xcframework_output_name "${MODULE}")-${LIBRARY_VERSION}.xcframework"
  else
    OUTPUT_PREFIX="$(resolve_xcframework_output_name "${MODULE}")"
    if [[ "${CONFIGURATION}" == "debug" ]]; then
      MODULE_OUTPUT_PATH="dist/${LIBRARY_VERSION}/ios/${OUTPUT_PREFIX}-${LIBRARY_VERSION}-debug.xcframework"
    else
      MODULE_OUTPUT_PATH="dist/${LIBRARY_VERSION}/ios/${OUTPUT_PREFIX}-${LIBRARY_VERSION}.xcframework"
    fi
  fi

  if [[ "${MODULE_OUTPUT_PATH}" = /* ]]; then
    XCFRAMEWORK_TARGET="${MODULE_OUTPUT_PATH}"
  else
    XCFRAMEWORK_TARGET="${ROOT_DIR}/${MODULE_OUTPUT_PATH}"
  fi

  MODULE_DEVICE_FRAMEWORK="${MODULE_DEVICE_ARCHIVE_PATH}/Products/Library/Frameworks/${MODULE_FRAMEWORK}.framework"
  MODULE_SIM_FRAMEWORK="${MODULE_SIM_ARCHIVE_PATH}/Products/Library/Frameworks/${MODULE_FRAMEWORK}.framework"

  if [[ ! -d "${MODULE_DEVICE_FRAMEWORK}" ]]; then
    echo "Error: Device framework not found at ${MODULE_DEVICE_FRAMEWORK}" >&2
    exit 1
  fi

  if [[ ! -d "${MODULE_SIM_FRAMEWORK}" ]]; then
    echo "Error: Simulator framework not found at ${MODULE_SIM_FRAMEWORK}" >&2
    exit 1
  fi

  mkdir -p "$(dirname -- "${XCFRAMEWORK_TARGET}")"
  rm -rf "${XCFRAMEWORK_TARGET}"

  echo "[package] [${MODULE}] Creating XCFramework"
  xcodebuild -create-xcframework \
    -framework "${MODULE_DEVICE_FRAMEWORK}" \
    -framework "${MODULE_SIM_FRAMEWORK}" \
    -output "${XCFRAMEWORK_TARGET}"

  echo "[done] [${MODULE}] Created ${XCFRAMEWORK_TARGET}"

  if [[ "${MODULE}" == "IosLibraryCApi" ]]; then
    # The loose copy of the public headers, for tools that read headers only (README 3,
    # C ABI design part 1, 5.2). check_ios_dist.py compares it with the framework's Headers/.
    HEADERS_TARGET="$(dirname -- "${XCFRAMEWORK_TARGET}")/include/NativeToolkitC"
    guard_headers_target "${HEADERS_TARGET}"
    rm -rf "${HEADERS_TARGET:?}"
    mkdir -p "${HEADERS_TARGET}"
    cp "${HEADERS_SOURCE}/"*.h "${HEADERS_TARGET}/"
    echo "[done] [${MODULE}] Copied the public headers to ${HEADERS_TARGET}"
  fi
done
