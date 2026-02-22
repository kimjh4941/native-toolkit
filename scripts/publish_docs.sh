#!/usr/bin/env bash
set -euo pipefail

# Publish versioned documentation and refresh docs/latest from the highest version.
#
# Usage:
#   ./scripts/publish_docs.sh <version> [--skip-build]
#
# Examples:
#   ./scripts/publish_docs.sh 1.0.0
#   ./scripts/publish_docs.sh 1.0.0 --skip-build

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/publish_docs.sh <version> [--skip-build]

Creates/updates:
  docs/<version>/...
  docs/latest/...
  (latest is refreshed from the highest version under docs/)

By default, this script tries to generate docs first:
  - Android: Dokka (android_library, unity_android_plugin)
  - iOS: DocC via ios/generate_docc.sh
  - macOS: DocC via mac/generate_docc.sh
  - Windows: Doxygen if `doxygen` is available

If you already generated docs manually, pass --skip-build to only copy/refresh.

Manual source is expected at:
  manual/<version>/
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

VERSION=${1:-}
SKIP_BUILD=false

if [[ -z "$VERSION" ]]; then
  echo "Error: <version> is required." >&2
  usage
  exit 1
fi

if [[ ${2:-} == "--skip-build" ]]; then
  SKIP_BUILD=true
elif [[ -n ${2:-} ]]; then
  echo "Error: unknown argument: ${2}" >&2
  usage
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

DOCS_ROOT="${ROOT_DIR}/docs"
VERSION_DIR="${DOCS_ROOT}/${VERSION}"
LATEST_DIR="${DOCS_ROOT}/latest"
MANUAL_SRC_DIR="${ROOT_DIR}/manual/${VERSION}"

copy_dir() {
  local src=$1
  local dst=$2
  if [[ ! -d "$src" ]]; then
    echo "[skip] Missing directory: $src" >&2
    return 0
  fi
  rm -rf "$dst"
  mkdir -p "$(dirname -- "$dst")"
  cp -R "$src" "$dst"
  echo "[copy] $src -> $dst"
}

run_if_exists() {
  local cmd=$1
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

version_gt() {
  local left=$1
  local right=$2
  local left_parts right_parts
  local i max_len

  IFS='.' read -r -a left_parts <<< "$left"
  IFS='.' read -r -a right_parts <<< "$right"
  max_len=${#left_parts[@]}
  if (( ${#right_parts[@]} > max_len )); then
    max_len=${#right_parts[@]}
  fi

  for (( i=0; i<max_len; i++ )); do
    local left_num=${left_parts[i]:-0}
    local right_num=${right_parts[i]:-0}
    if (( 10#${left_num} > 10#${right_num} )); then
      return 0
    fi
    if (( 10#${left_num} < 10#${right_num} )); then
      return 1
    fi
  done

  return 1
}

resolve_highest_docs_version() {
  local highest=""
  local dir_name

  while IFS= read -r dir_name; do
    [[ "$dir_name" == "latest" ]] && continue
    [[ "$dir_name" =~ ^[0-9]+([.][0-9]+)*$ ]] || continue
    if [[ -z "$highest" ]] || version_gt "$dir_name" "$highest"; then
      highest="$dir_name"
    fi
  done < <(find "$DOCS_ROOT" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)

  printf '%s' "$highest"
}

generate_android() {
  local android_root="${ROOT_DIR}/android/AndroidLibraryExample"
  if [[ ! -x "${android_root}/gradlew" ]]; then
    echo "[skip] Android gradlew not found: ${android_root}/gradlew" >&2
    return 0
  fi
  echo "[build] Android Dokka"
  (cd "$android_root" && ./gradlew :android_library:clean :android_library:dokkaHtml :unity_android_plugin:clean :unity_android_plugin:dokkaHtml)
}

generate_ios() {
  local ios_script="${ROOT_DIR}/ios/generate_docc.sh"
  if [[ ! -f "$ios_script" ]]; then
    echo "[skip] iOS doc script not found: $ios_script" >&2
    return 0
  fi
  echo "[build] iOS DocC"
  (cd "${ROOT_DIR}/ios" && ./generate_docc.sh)
}

generate_mac() {
  local mac_script="${ROOT_DIR}/mac/generate_docc.sh"
  if [[ ! -f "$mac_script" ]]; then
    echo "[skip] macOS doc script not found: $mac_script" >&2
    return 0
  fi
  echo "[build] macOS DocC"
  (cd "${ROOT_DIR}/mac" && ./generate_docc.sh)
}

generate_windows() {
  local doxyfile="${ROOT_DIR}/windows/WindowsLibrary/Doxyfile"
  if [[ ! -f "$doxyfile" ]]; then
    echo "[skip] Windows Doxyfile not found: $doxyfile" >&2
    return 0
  fi
  if run_if_exists doxygen; then
    echo "[build] Windows Doxygen"
    (cd "${ROOT_DIR}/windows/WindowsLibrary" && doxygen Doxyfile)
  else
    echo "[skip] doxygen not found; skipping Windows doc generation" >&2
  fi
}

echo "Publishing docs for version: ${VERSION}"
mkdir -p "$DOCS_ROOT"

if [[ "$SKIP_BUILD" == "false" ]]; then
  generate_android
  generate_ios
  generate_mac
  generate_windows
else
  echo "[info] --skip-build set; copying existing outputs only"
fi

echo "[stage] Copying into ${VERSION_DIR}"
rm -rf "$VERSION_DIR"
mkdir -p "$VERSION_DIR"

# Android
copy_dir "${ROOT_DIR}/android/android_library/build/dokka/html" "${VERSION_DIR}/android/android_library"
copy_dir "${ROOT_DIR}/android/unity_android_plugin/build/dokka/html" "${VERSION_DIR}/android/unity_android_plugin"

# iOS
copy_dir "${ROOT_DIR}/ios/Docs/IosLibrary" "${VERSION_DIR}/ios/IosLibrary"
copy_dir "${ROOT_DIR}/ios/Docs/UnityIosPlugin" "${VERSION_DIR}/ios/UnityIosPlugin"

# macOS
copy_dir "${ROOT_DIR}/mac/Docs/MacLibrary" "${VERSION_DIR}/mac/MacLibrary"
copy_dir "${ROOT_DIR}/mac/Docs/UnityMacPlugin" "${VERSION_DIR}/mac/UnityMacPlugin"

# Windows
copy_dir "${ROOT_DIR}/windows/WindowsLibrary/docs/html" "${VERSION_DIR}/windows/WindowsLibrary"

# Manual (versioned source)
copy_dir "${MANUAL_SRC_DIR}" "${VERSION_DIR}/manual"

LATEST_VERSION="$(resolve_highest_docs_version)"
if [[ -z "$LATEST_VERSION" ]]; then
  echo "Error: no version directories found under ${DOCS_ROOT}." >&2
  exit 1
fi

echo "[latest] Refreshing ${LATEST_DIR} -> ${LATEST_VERSION}"
rm -rf "$LATEST_DIR"
copy_dir "${DOCS_ROOT}/${LATEST_VERSION}" "$LATEST_DIR"

echo "$LATEST_VERSION" > "${LATEST_DIR}/VERSION.txt"
echo "[latest] Wrote ${LATEST_DIR}/VERSION.txt"

echo "Done. Open docs entry: ${DOCS_ROOT}/index.html"
