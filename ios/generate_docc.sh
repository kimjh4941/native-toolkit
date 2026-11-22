#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIR"

# Define variables for IosLibrary
IOSLIBRARY_BUILD_PATH="Build/IosLibrary"
IOSLIBRARY_PROJECT_PATH="IosLibrary/IosLibrary.xcodeproj"
IOSLIBRARY_SCHEME="IosLibrary"
IOSLIBRARY_DESTINATION="generic/platform=iOS"
IOSLIBRARY_OUTPUT_PATH="$PWD/Docs/IosLibrary"
IOSLIBRARY_HOSTING_BASE_PATH="IosLibrary"

clean_docc() {
    local build_path=$1
    local output_path=$2

    echo "Cleaning docc build/output..."

    if [ -e "$build_path" ]; then
        echo "Removing existing build: $build_path"
        rm -rf "$build_path"
    fi

    if [ -e "$output_path" ]; then
        echo "Removing existing output: $output_path"
        rm -rf "$output_path"
    fi
}

generate_docc() {
    local project=$1
    local scheme=$2
    local destination=$3
    local derived_data_path=$4
    local output_path=$5
    local hosting_base_path=$6

    echo "Running xcodebuild docbuild for $scheme..."
    # Run docbuild for the target
    BUILD_LIBRARY_FOR_DISTRIBUTION=NO xcodebuild docbuild \
      -project "$project" \
      -scheme "$scheme" \
      -destination "$destination" \
      -derivedDataPath "$derived_data_path"

    echo "Searching for .doccarchive..."
    local found_archive
    found_archive=$(find "$derived_data_path" -type d -name "*.doccarchive" -print -quit || true)
    if [ -z "$found_archive" ]; then
        echo "Error: .doccarchive not found under $derived_data_path" >&2
        return 1
    fi
    echo "Found archive: $found_archive"

    mkdir -p "$output_path"

    echo "Converting .doccarchive to static site..."
    xcrun docc process-archive transform-for-static-hosting \
      "$found_archive" \
      --output-path "$output_path" \
      --hosting-base-path "$hosting_base_path"
      
    echo "Output index:"
    ls -la "$output_path/index.html"
}

# Generate DocC for IosLibrary (build + docbuild)
clean_docc "$IOSLIBRARY_BUILD_PATH" "$IOSLIBRARY_OUTPUT_PATH"
generate_docc "$IOSLIBRARY_PROJECT_PATH" "$IOSLIBRARY_SCHEME" "$IOSLIBRARY_DESTINATION" "$IOSLIBRARY_BUILD_PATH" "$IOSLIBRARY_OUTPUT_PATH" "$IOSLIBRARY_HOSTING_BASE_PATH"

echo "DocC generation completed."
