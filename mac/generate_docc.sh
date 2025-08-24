#!/usr/bin/env bash
set -euo pipefail

cd /Users/jonghyunkim/Desktop/native-toolkit/mac

# Define variables for MacLibrary
MACLIBRARY_BUILD_PATH="Build/MacLibrary"
MACLIBRARY_PROJECT_PATH="MacLibrary/MacLibrary.xcodeproj"
MACLIBRARY_SCHEME="MacLibrary"
MACLIBRARY_DESTINATION="generic/platform=macOS"
MACLIBRARY_OUTPUT_PATH="$PWD/Docs/MacLibrary"
MACLIBRARY_HOSTING_BASE_PATH="MacLibrary"

# Define variables for UnityMacPlugin
UNITYMACPLUGIN_BUILD_PATH="Build/UnityMacPlugin"
UNITYMACPLUGIN_PROJECT_PATH="UnityMacPlugin/UnityMacPlugin.xcodeproj"
UNITYMACPLUGIN_SCHEME="UnityMacPlugin"
UNITYMACPLUGIN_DESTINATION="generic/platform=macOS"
UNITYMACPLUGIN_OUTPUT_PATH="$PWD/Docs/UnityMacPlugin"
UNITYMACPLUGIN_HOSTING_BASE_PATH="UnityMacPlugin"

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

build_project() {
    local project=$1
    local scheme=$2
    local destination=$3
    local derived_data_path=$4

    echo "Building project $project (scheme: $scheme) ..."
    BUILD_LIBRARY_FOR_DISTRIBUTION=NO xcodebuild build \
      -project "$project" \
      -scheme "$scheme" \
      -destination "$destination" \
      -derivedDataPath "$derived_data_path" \
      -sdk macosx
}

generate_docc() {
    local project=$1
    local scheme=$2
    local destination=$3
    local derived_data_path=$4
    local output_path=$5
    local hosting_base_path=$6

    echo "Running xcodebuild docbuild for $scheme..."
    # If building UnityMacPlugin, ensure MacLibrary is built first so the module is available
    if [ "$scheme" = "$UNITYMACPLUGIN_SCHEME" ]; then
        if [ -n "$MACLIBRARY_PROJECT_PATH" ]; then
            build_project "$MACLIBRARY_PROJECT_PATH" "$MACLIBRARY_SCHEME" "$MACLIBRARY_DESTINATION" "$derived_data_path"
        fi
    fi

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

# Generate DocC for MacLibrary (build + docbuild)
clean_docc "$MACLIBRARY_BUILD_PATH" "$MACLIBRARY_OUTPUT_PATH"
generate_docc "$MACLIBRARY_PROJECT_PATH" "$MACLIBRARY_SCHEME" "$MACLIBRARY_DESTINATION" "$MACLIBRARY_BUILD_PATH" "$MACLIBRARY_OUTPUT_PATH" "$MACLIBRARY_HOSTING_BASE_PATH"

# Generate DocC for UnityMacPlugin (build MacLibrary first if needed, then docbuild)
clean_docc "$UNITYMACPLUGIN_BUILD_PATH" "$UNITYMACPLUGIN_OUTPUT_PATH"
generate_docc "$UNITYMACPLUGIN_PROJECT_PATH" "$UNITYMACPLUGIN_SCHEME" "$UNITYMACPLUGIN_DESTINATION" "$UNITYMACPLUGIN_BUILD_PATH" "$UNITYMACPLUGIN_OUTPUT_PATH" "$UNITYMACPLUGIN_HOSTING_BASE_PATH"

echo "DocC generation completed."
