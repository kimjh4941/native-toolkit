#!/usr/bin/env bash
set -euo pipefail

# Build one or more Android library module AARs and copy them with distributable names.
#
# Usage:
#   ./scripts/build_android_library_aar.sh [--module <name>]... [--build-type <debug|release>] [--library-version <version>] [--output <path>] [--log-file <path>]
#
# Examples:
#   ./scripts/build_android_library_aar.sh --library-version 1.1.0
#   ./scripts/build_android_library_aar.sh --build-type debug
#   ./scripts/build_android_library_aar.sh --module unity_android_plugin --library-version 1.1.0
#   ./scripts/build_android_library_aar.sh --module android_library --module unity_android_plugin --library-version 1.1.0
#   ./scripts/build_android_library_aar.sh --build-type release --output dist/1.1.0/android/android-native-toolkit-1.1.0.aar
#   ./scripts/build_android_library_aar.sh --build-type release --library-version 1.1.0 --log-file dist/1.1.0/android/build-1.1.0.log
#   ./scripts/build_android_library_aar.sh -b debug -m android_library -v 1.1.0 -o /tmp/NativeToolkit-debug.aar
#   ./scripts/build_android_library_aar.sh -b release -m android_library -v 1.3.0 -o dist/1.8.0/android/android-native-toolkit-1.3.0.aar
#   ./scripts/build_android_library_aar.sh -b release -m unity_android_plugin -v 1.3.0 -o dist/1.8.0/android/unity-android-native-toolkit-1.3.0.aar
#   ./scripts/build_android_library_aar.sh -m android_library -m android_library_capi -v 2.0.0 --m2

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

ANDROID_GRADLE_ROOT="${ROOT_DIR}/android"
GRADLE_PROPERTIES_PATH="${ANDROID_GRADLE_ROOT}/gradle.properties"

BUILD_TYPE="release"
MODULES=()
OUTPUT_PATH=""
OUTPUT_PATH_SET=false
LIBRARY_VERSION=""
LOG_PATH=""
LOG_PATH_SET=false
PUBLISH_M2=false

usage() {
  cat <<'USAGE'
Build one or more Android library module AARs and copy them to target paths.

Usage:
  ./scripts/build_android_library_aar.sh [--module <name>]... [--build-type <debug|release>] [--library-version <version>] [--output <path>] [--log-file <path>] [--m2]

Options:
  -m, --module       Module to build (repeatable). Examples: android_library, android_library_capi,
                     unity_android_plugin
                     Default: android_library
  -b, --build-type   Build type to assemble (debug or release). Default: release
  -v, --library-version
                     Library version to include in default output naming.
                     Example default with version: dist/<version>/android/android-native-toolkit-<version>.aar
  -o, --output       Output AAR path. Relative paths are resolved from repository root.
                     Default (when omitted): per-module default output path
                     android_library: dist/<version>/android/android-native-toolkit-<version>.aar
                     android_library_capi: dist/<version>/android/android-native-toolkit-capi-<version>.aar
                       (a release build there also copies the C headers to dist/<version>/android/include/)
                     unity_android_plugin: dist/<version>/android/unity-android-native-toolkit-<version>.aar
                     Note: --library-version is required when --output is omitted.
                     Note: --output is allowed only for single-module builds.
  -l, --log-file     Build log file path. Relative paths are resolved from repository root.
                     Default (single module): <output-path-without-extension>.log
                     Default (multi module):  dist/<version>/android/build-<version>.log
      --m2           Also publish the modules' Maven publications (POM and Gradle Module Metadata) and
                     replace dist/<version>/android/m2/ with them (README D-17). Release only; with
                     android_library_capi, android_library has to be built too (the capi POM depends on it).
  -h, --help         Show this help message.
USAGE
}

module_output_prefix() {
  local module=$1
  case "${module}" in
    android_library)
      echo "android-native-toolkit"
      ;;
    android_library_capi)
      echo "android-native-toolkit-capi"
      ;;
    unity_android_plugin)
      echo "unity-android-native-toolkit"
      ;;
    *)
      echo "${module}"
      ;;
  esac
}

# The Gradle project of a module directory: android_library_capi is :ntk, so that consumers write
# find_package(ntk) and ntk::ntk (C ABI design part 1, AC-13). Its AAR is named after the project.
module_project() {
  local module=$1
  case "${module}" in
    android_library_capi)
      echo "ntk"
      ;;
    *)
      echo "${module}"
      ;;
  esac
}

module_task() {
  local module=$1
  local task_suffix="assembleRelease"
  if [[ "${BUILD_TYPE}" == "debug" ]]; then
    task_suffix="assembleDebug"
  fi
  echo ":$(module_project "${module}"):${task_suffix}"
}

validate_module() {
  local module=$1
  local module_dir="${ROOT_DIR}/android/${module}"
  if [[ ! -d "${module_dir}" ]]; then
    echo "Error: Unknown module '${module}'. Expected directory: ${module_dir}" >&2
    exit 1
  fi
  if [[ ! -f "${module_dir}/build.gradle.kts" ]]; then
    echo "Error: Module '${module}' is missing build.gradle.kts at ${module_dir}/build.gradle.kts" >&2
    exit 1
  fi
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
    -l|--log-file)
      if [[ $# -lt 2 ]]; then
        echo "Error: --log-file requires a value." >&2
        usage
        exit 1
      fi
      LOG_PATH="$2"
      LOG_PATH_SET=true
      shift 2
      ;;
    --m2)
      PUBLISH_M2=true
      shift
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

if [[ ${#MODULES[@]} -eq 0 ]]; then
  MODULES=("android_library")
fi

for module in "${MODULES[@]}"; do
  validate_module "${module}"
done

if [[ "${OUTPUT_PATH_SET}" == "true" && ${#MODULES[@]} -ne 1 ]]; then
  echo "Error: --output is only supported when building a single module." >&2
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

if [[ "${OUTPUT_PATH_SET}" == "false" ]]; then
  if [[ -z "${LIBRARY_VERSION}" ]]; then
    echo "Error: --library-version is required when --output is omitted." >&2
    usage
    exit 1
  fi
fi

has_module() {
  local wanted=$1
  local module
  for module in "${MODULES[@]}"; do
    [[ "${module}" == "${wanted}" ]] && return 0
  done
  return 1
}

if [[ "${PUBLISH_M2}" == "true" ]]; then
  if [[ "${BUILD_TYPE}" != "release" || -z "${LIBRARY_VERSION}" ]]; then
    echo "Error: --m2 needs --build-type release and --library-version." >&2
    usage
    exit 1
  fi
  if has_module android_library_capi && ! has_module android_library; then
    echo "Error: --m2 with android_library_capi needs android_library too (the capi POM depends on it)." >&2
    exit 1
  fi
fi

GRADLE_TASKS=()
MODULE_SOURCES=()
MODULE_TARGETS=()
for module in "${MODULES[@]}"; do
  GRADLE_TASKS+=("$(module_task "${module}")")
  if [[ "${PUBLISH_M2}" == "true" ]]; then
    GRADLE_TASKS+=(":$(module_project "${module}"):publishReleasePublicationToMavenRepository")
  fi
  MODULE_SOURCES+=("${ROOT_DIR}/android/${module}/build/outputs/aar/$(module_project "${module}")-${BUILD_TYPE}.aar")

  if [[ "${OUTPUT_PATH_SET}" == "true" ]]; then
    if [[ "${OUTPUT_PATH}" = /* ]]; then
      MODULE_TARGETS+=("${OUTPUT_PATH}")
    else
      MODULE_TARGETS+=("${ROOT_DIR}/${OUTPUT_PATH}")
    fi
  else
    output_prefix="$(module_output_prefix "${module}")"
    if [[ "${BUILD_TYPE}" == "debug" ]]; then
      MODULE_TARGETS+=("${ROOT_DIR}/dist/${LIBRARY_VERSION}/android/${output_prefix}-${LIBRARY_VERSION}-debug.aar")
    else
      MODULE_TARGETS+=("${ROOT_DIR}/dist/${LIBRARY_VERSION}/android/${output_prefix}-${LIBRARY_VERSION}.aar")
    fi
  fi
done

if [[ "${LOG_PATH_SET}" == "false" ]]; then
  if [[ ${#MODULES[@]} -eq 1 ]]; then
    BUILD_LOG_TARGET="${MODULE_TARGETS[0]%.*}.log"
  else
    BUILD_LOG_TARGET="${ROOT_DIR}/dist/${LIBRARY_VERSION}/android/build-${LIBRARY_VERSION}.log"
  fi
elif [[ "${LOG_PATH}" = /* ]]; then
  BUILD_LOG_TARGET="${LOG_PATH}"
else
  BUILD_LOG_TARGET="${ROOT_DIR}/${LOG_PATH}"
fi

if [[ ! -x "${ANDROID_GRADLE_ROOT}/gradlew" ]]; then
  echo "Error: Gradle wrapper not found at ${ANDROID_GRADLE_ROOT}/gradlew" >&2
  exit 1
fi

update_library_version_property() {
  local properties_path=$1
  local next_version=$2
  local tmp_file

  if [[ ! -f "${properties_path}" ]]; then
    echo "Error: gradle.properties not found at ${properties_path}" >&2
    exit 1
  fi

  tmp_file="$(mktemp)"
  awk -v version="${next_version}" '
    BEGIN { updated = 0 }
    /^libraryVersion[[:space:]]*=/ {
      print "libraryVersion=" version
      updated = 1
      next
    }
    { print }
    END {
      if (updated == 0) {
        print "libraryVersion=" version
      }
    }
  ' "${properties_path}" > "${tmp_file}"

  mv "${tmp_file}" "${properties_path}"
}

PREFERRED_JAVA_HOME="/Applications/Android Studio Panda 1 .app/Contents/jbr/Contents/Home"
PREFERRED_JAVA_HOME_ALT="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

if [[ -d "${PREFERRED_JAVA_HOME}" ]]; then
  export JAVA_HOME="${PREFERRED_JAVA_HOME}"
  echo "[info] Using preferred JAVA_HOME: ${JAVA_HOME}"
elif [[ -d "${PREFERRED_JAVA_HOME_ALT}" ]]; then
  export JAVA_HOME="${PREFERRED_JAVA_HOME_ALT}"
  echo "[info] Using fallback JAVA_HOME: ${JAVA_HOME}"
fi

echo "[build] Building modules (${MODULES[*]}) ${BUILD_TYPE} AAR"
echo "[log] Build output will be saved to ${BUILD_LOG_TARGET}"
GRADLE_ARGS=("${GRADLE_TASKS[@]}")
if [[ -n "${LIBRARY_VERSION}" ]]; then
  update_library_version_property "${GRADLE_PROPERTIES_PATH}" "${LIBRARY_VERSION}"
  echo "[info] Updated gradle.properties libraryVersion=${LIBRARY_VERSION}"
  GRADLE_ARGS+=("-PlibraryVersion=${LIBRARY_VERSION}")
fi

M2_BUILD_DIR="${ANDROID_GRADLE_ROOT}/build/m2"
if [[ "${PUBLISH_M2}" == "true" ]]; then
  # Only this build's publications go into the repository.
  rm -rf "${M2_BUILD_DIR}"
fi

mkdir -p "$(dirname -- "${BUILD_LOG_TARGET}")"
(cd "${ANDROID_GRADLE_ROOT}" && ./gradlew "${GRADLE_ARGS[@]}") 2>&1 | tee "${BUILD_LOG_TARGET}"

for i in "${!MODULES[@]}"; do
  module="${MODULES[$i]}"
  aar_source="${MODULE_SOURCES[$i]}"
  aar_target="${MODULE_TARGETS[$i]}"

  if [[ ! -f "${aar_source}" ]]; then
    echo "Error: AAR not found for module '${module}' at ${aar_source}" >&2
    exit 1
  fi

  mkdir -p "$(dirname -- "${aar_target}")"
  if [[ -f "${aar_target}" ]]; then
    rm -f "${aar_target}"
  fi
  cp "${aar_source}" "${aar_target}"
  echo "[done] Created ${aar_target}"
done

# The C headers next to the capi AAR, for binding generators (README D-9).
if has_module android_library_capi && [[ "${BUILD_TYPE}" == "release" && "${OUTPUT_PATH_SET}" == "false" ]]; then
  headers_target="${ROOT_DIR}/dist/${LIBRARY_VERSION}/android/include/NativeToolkitC"
  rm -rf "${headers_target}"
  mkdir -p "${headers_target}"
  cp "${ROOT_DIR}/android/android_library_capi/src/main/cpp/include/NativeToolkitC/"*.h "${headers_target}/"
  echo "[done] Copied the C headers to ${headers_target}"
fi

if [[ "${PUBLISH_M2}" == "true" ]]; then
  m2_target="${ROOT_DIR}/dist/${LIBRARY_VERSION}/android/m2"
  if [[ ! -d "${M2_BUILD_DIR}" ]]; then
    echo "Error: the Maven repository was not created at ${M2_BUILD_DIR}" >&2
    exit 1
  fi
  rm -rf "${m2_target}"
  mkdir -p "$(dirname -- "${m2_target}")"
  cp -R "${M2_BUILD_DIR}" "${m2_target}"
  echo "[done] Created the Maven repository ${m2_target}"
fi
