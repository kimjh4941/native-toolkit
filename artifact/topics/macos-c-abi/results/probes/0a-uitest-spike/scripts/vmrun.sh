#!/bin/zsh
# usage (inside VM): vmrun.sh <tag> <only-testing...>  ; DEVELOPER_DIR may be set by caller
cd ~/ntk/src/mac
TAG=$1; shift
DD=${DD:-~/ntk/dd263}
ARGS=(); for t in "$@"; do ARGS+=(-only-testing:$t); done
xcodebuild build-for-testing -workspace MacWorkspace.xcworkspace -scheme MacLibraryExample -destination "platform=macOS,arch=arm64" -derivedDataPath $DD CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= > ~/ntk/build-$TAG.log 2>&1 || { echo BUILD FAILED; grep error: ~/ntk/build-$TAG.log | head; exit 1; }
rm -rf ~/ntk/r-$TAG.xcresult
xcodebuild test-without-building -workspace MacWorkspace.xcworkspace -scheme MacLibraryExample -destination "platform=macOS,arch=arm64" -derivedDataPath $DD "${ARGS[@]}" -resultBundlePath ~/ntk/r-$TAG.xcresult > ~/ntk/ui-$TAG.log 2>&1
echo exit=$?
grep -E "Test Case .*(passed|failed|skipped)|error:" ~/ntk/ui-$TAG.log
