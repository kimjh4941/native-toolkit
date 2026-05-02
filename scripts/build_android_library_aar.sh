#!/usr/bin/env bash
set -euo pipefail

# Build android_library AAR and copy it with a distributable name.
#
# Usage:
#   ./scripts/build_android_library_aar.sh [--build-type <debug|release>] [--library-version <version>] [--output <path>] [--log-file <path>]
#
# Examples:
#   ./scripts/build_android_library_aar.sh --library-version 1.1.0
#   ./scripts/build_android_library_aar.sh --build-type debug
#   ./scripts/build_android_library_aar.sh --library-version 1.1.0
#   ./scripts/build_android_library_aar.sh --build-type release --output dist/1.1.0/android/native-toolkit-1.1.0.aar
#   ./scripts/build_android_library_aar.sh --build-type release --library-version 1.1.0 --log-file dist/1.1.0/android/native-toolkit-1.1.0-build.log
#   ./scripts/build_android_library_aar.sh -b debug -v 1.1.0 -o /tmp/NativeToolkit-debug.aar

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

ANDROID_EXAMPLE_DIR="${ROOT_DIR}/android/AndroidLibraryExample"
GRADLE_PROPERTIES_PATH="${ANDROID_EXAMPLE_DIR}/gradle.properties"

BUILD_TYPE="release"
OUTPUT_PATH=""
OUTPUT_PATH_SET=false
LIBRARY_VERSION=""
LOG_PATH=""
LOG_PATH_SET=false

usage() {
  cat <<'USAGE'
Build android_library AAR and copy it to a target path.

Usage:
  ./scripts/build_android_library_aar.sh [--build-type <debug|release>] [--library-version <version>] [--output <path>] [--log-file <path>]

Options:
  -b, --build-type   Build type to assemble (debug or release). Default: release
  -v, --library-version
                     Library version to include in default output naming.
                     Example default with version: dist/<version>/android/native-toolkit-<version>.aar
  -o, --output       Output AAR path. Relative paths are resolved from repository root.
                     Default (when omitted): dist/<version>/android/native-toolkit-<version>.aar
                     Note: --library-version is required when --output is omitted.
  -l, --log-file     Build log file path. Relative paths are resolved from repository root.
                     Default: <output-path-without-extension>.log
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
  OUTPUT_PATH="dist/${LIBRARY_VERSION}/android/native-toolkit-${LIBRARY_VERSION}.aar"
fi

if [[ "${OUTPUT_PATH}" = /* ]]; then
  AAR_TARGET="${OUTPUT_PATH}"
else
  AAR_TARGET="${ROOT_DIR}/${OUTPUT_PATH}"
fi

if [[ "${LOG_PATH_SET}" == "false" ]]; then
  BUILD_LOG_TARGET="${AAR_TARGET%.*}.log"
elif [[ "${LOG_PATH}" = /* ]]; then
  BUILD_LOG_TARGET="${LOG_PATH}"
else
  BUILD_LOG_TARGET="${ROOT_DIR}/${LOG_PATH}"
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

echo "[build] Building android_library ${BUILD_TYPE} AAR"
echo "[log] Build output will be saved to ${BUILD_LOG_TARGET}"
GRADLE_ARGS=("${GRADLE_TASK}")
if [[ -n "${LIBRARY_VERSION}" ]]; then
  update_library_version_property "${GRADLE_PROPERTIES_PATH}" "${LIBRARY_VERSION}"
  echo "[info] Updated gradle.properties libraryVersion=${LIBRARY_VERSION}"
  GRADLE_ARGS+=("-PlibraryVersion=${LIBRARY_VERSION}")
fi

mkdir -p "$(dirname -- "${BUILD_LOG_TARGET}")"
(cd "${ANDROID_EXAMPLE_DIR}" && ./gradlew "${GRADLE_ARGS[@]}") 2>&1 | tee "${BUILD_LOG_TARGET}"

if [[ ! -f "${AAR_SOURCE}" ]]; then
  echo "Error: AAR not found at ${AAR_SOURCE}" >&2
  exit 1
fi

mkdir -p "$(dirname -- "${AAR_TARGET}")"
if [[ -f "${AAR_TARGET}" ]]; then
  rm -f "${AAR_TARGET}"
fi
cp "${AAR_SOURCE}" "${AAR_TARGET}"

echo "[done] Created ${AAR_TARGET}"
